#!/usr/bin/env python3
"""ncdb - NeoCoreFX hardware debug client."""

from __future__ import annotations

import argparse
import shlex
import struct
import sys
import time
from dataclasses import dataclass

SOF_REQ = 0xA5
SOF_RESP = 0x5A

CMD_HELLO = 0x00
CMD_HALT = 0x10
CMD_RESUME = 0x11
CMD_STEP = 0x12
CMD_SET_PC = 0x13
CMD_READ_STATUS = 0x20
CMD_READ_GPR = 0x21
CMD_WRITE_GPR = 0x22
CMD_READ_MEM = 0x23
CMD_WRITE_MEM = 0x24
CMD_READ_COUNTERS = 0x25
CMD_READ_MEM_BURST = 0x26
CMD_SET_MEM_BURST = 0x27

HALT_OPCODE = 0x40000000  # ISA canonical B .

STATUS_NAMES = {
    0x00: "OK",
    0x01: "CRC_ERR",
    0x02: "BAD_CMD",
    0x03: "BUS_ERR",
    0x04: "BUSY",
    0x05: "NOT_HALTED",
    0x06: "TIMEOUT",
}

HALT_REASON_NAMES = {
    0: "none",
    1: "bdot",
    2: "debug_req",
    3: "debug_step",
}


@dataclass
class Frame:
    seq: int
    status: int
    payload: bytes


class StreamDemux:
    """Split serial RX stream into debug response frames and human console bytes."""

    def __init__(self, ser) -> None:
        self.ser = ser
        self.frames: list[Frame] = []
        self.console = bytearray()
        self._cand = bytearray()
        self._cand_need = -1
        self._cand_started = 0.0

    def _flush_candidate_to_console(self) -> None:
        if self._cand:
            self.console.extend(self._cand)
        self._cand.clear()
        self._cand_need = -1
        self._cand_started = 0.0

    def _feed_byte(self, b: int) -> None:
        now = time.time()

        if not self._cand:
            if b == SOF_RESP:
                self._cand.append(b)
                self._cand_started = now
                self._cand_need = -1
            else:
                self.console.append(b)
            return

        self._cand.append(b)

        if len(self._cand) == 4:
            payload_len = self._cand[3]
            if payload_len > 32:
                self._flush_candidate_to_console()
                return
            self._cand_need = 4 + payload_len + 2

        if self._cand_need > 0 and len(self._cand) >= self._cand_need:
            raw = bytes(self._cand[: self._cand_need])
            header = raw[:4]
            payload = raw[4:-2]
            got_crc = (raw[-2] << 8) | raw[-1]
            calc_crc = crc16_ccitt(header + payload)
            if calc_crc == got_crc:
                self.frames.append(Frame(seq=header[1], status=header[2], payload=payload))
            else:
                self.console.extend(raw)

            # Keep any overflow bytes (shouldn't happen in byte-at-a-time feed, but safe).
            tail = self._cand[self._cand_need :]
            self._cand.clear()
            self._cand_need = -1
            self._cand_started = 0.0
            for tb in tail:
                self._feed_byte(tb)

    def poll(self, max_reads: int = 1024) -> None:
        reads = 0
        while reads < max_reads:
            b = self.ser.read(1)
            if not b:
                break
            self._feed_byte(b[0])
            reads += 1

        # If we started parsing a possible frame and stream went idle, eventually release it.
        if self._cand and (time.time() - self._cand_started) > 0.2:
            self._flush_candidate_to_console()

    def pop_console_bytes(self) -> bytes:
        if not self.console:
            return b""
        out = bytes(self.console)
        self.console.clear()
        return out

    def pop_frame_for_seq(self, seq: int) -> Frame | None:
        for i, fr in enumerate(self.frames):
            if fr.seq == (seq & 0xFF):
                return self.frames.pop(i)
        return None


def crc16_ccitt(data: bytes) -> int:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def build_frame(seq: int, cmd: int, payload: bytes) -> bytes:
    if len(payload) > 32:
        raise ValueError("payload too large")
    head = bytes([SOF_REQ, seq & 0xFF, cmd & 0xFF, len(payload) & 0xFF]) + payload
    crc = crc16_ccitt(head)
    return head + bytes([(crc >> 8) & 0xFF, crc & 0xFF])


def read_exact(ser, n: int, timeout_s: float) -> bytes:
    deadline = time.time() + timeout_s
    out = bytearray()
    while len(out) < n and time.time() < deadline:
        chunk = ser.read(n - len(out))
        if chunk:
            out.extend(chunk)
    if len(out) != n:
        raise TimeoutError(f"timed out reading {n} bytes, got {len(out)}")
    return bytes(out)


def read_response(ser, timeout_s: float) -> Frame:
    deadline = time.time() + timeout_s
    tail = bytearray()
    while time.time() < deadline:
        b = ser.read(1)
        if not b:
            continue
        tail.extend(b)
        if len(tail) > 64:
            del tail[: len(tail) - 64]
        if b[0] == SOF_RESP:
            header = bytes([b[0]]) + read_exact(ser, 3, timeout_s)
            seq = header[1]
            status = header[2]
            payload_len = header[3]
            if payload_len > 32:
                continue
            payload = read_exact(ser, payload_len, timeout_s)
            crc_bytes = read_exact(ser, 2, timeout_s)
            got_crc = (crc_bytes[0] << 8) | crc_bytes[1]
            calc_crc = crc16_ccitt(header + payload)
            if got_crc != calc_crc:
                continue
            return Frame(seq=seq, status=status, payload=payload)
    if tail:
        raise TimeoutError(f"timed out waiting for response SOF (tail={bytes(tail).hex()})")
    raise TimeoutError("timed out waiting for response SOF")


def sniff_bytes(ser, seconds: float) -> bytes:
    deadline = time.time() + max(0.05, seconds)
    out = bytearray()
    while time.time() < deadline:
        b = ser.read(1)
        if b:
            out.extend(b)
    return bytes(out)


def send_cmd(
    ser,
    seq: int,
    cmd: int,
    payload: bytes,
    timeout_s: float,
    tx_byte_delay_s: float = 0.0,
) -> Frame:
    frame = build_frame(seq, cmd, payload)
    if tx_byte_delay_s > 0.0:
        for b in frame:
            ser.write(bytes([b]))
            ser.flush()
            time.sleep(tx_byte_delay_s)
    else:
        ser.write(frame)
        ser.flush()
    resp = read_response(ser, timeout_s)
    if resp.seq != (seq & 0xFF):
        raise ValueError(f"response seq mismatch: got {resp.seq}, expected {seq & 0xFF}")
    return resp


def send_cmd_retry(
    ser,
    seq: int,
    cmd: int,
    payload: bytes,
    timeout_s: float,
    retries: int = 4,
    tx_byte_delay_s: float = 0.0,
) -> Frame:
    last_exc: Exception | None = None
    for attempt in range(max(1, retries)):
        try:
            return send_cmd(ser, seq, cmd, payload, timeout_s, tx_byte_delay_s=tx_byte_delay_s)
        except TimeoutError as exc:
            last_exc = exc
            ser.reset_input_buffer()
            if attempt + 1 < retries:
                time.sleep(0.05)
                continue
            raise
    if last_exc is not None:
        raise last_exc
    raise TimeoutError("command retries exhausted")


def unpack_words(payload: bytes) -> list[int]:
    if len(payload) % 4 != 0:
        return []
    return [int.from_bytes(payload[i : i + 4], "big") for i in range(0, len(payload), 4)]


def parse_status_payload(payload: bytes) -> dict[str, int]:
    words = unpack_words(payload)
    if len(words) < 5:
        return {}
    flags = words[0]
    return {
        "halted": flags & 0x1,
        "halt_reason": (flags >> 1) & 0x7,
        "last_fault": (flags >> 4) & 0x1,
        "pc": words[1],
        "fault_pc": words[2],
        "fault_addr": words[3],
        "illegal_inst": words[4],
    }


def status_name(code: int) -> str:
    return STATUS_NAMES.get(code, f"0x{code:02x}")


def halt_reason_name(code: int) -> str:
    return HALT_REASON_NAMES.get(code, f"{code}")


def mem_size_code(size: int) -> int:
    mapping = {1: 0, 2: 1, 4: 2}
    if size not in mapping:
        raise ValueError(f"invalid mem size: {size}")
    return mapping[size]


def positive_int(value: str) -> int:
    parsed = int(value, 0)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be > 0")
    return parsed


MAX_READ_BURST_WORDS = 8
MAX_SET_BURST_COUNT = 255


def run_tui(ser, timeout_s: float, tx_byte_delay_s: float) -> int:
    try:
        import curses
    except Exception as exc:
        print(f"tui mode requires curses: {exc}", file=sys.stderr)
        return 2

    old_timeout = ser.timeout
    ser.timeout = 0.0

    demux = StreamDemux(ser)
    seq = 1

    breakpoints: dict[int, int] = {}
    console_lines: list[str] = [""]
    log_lines: list[str] = []

    last_status: dict[str, int] = {}
    last_err = ""
    last_update = 0.0

    input_mode = "console"
    input_buf = ""

    def add_log(msg: str) -> None:
        ts = time.strftime("%H:%M:%S")
        log_lines.append(f"[{ts}] {msg}")
        if len(log_lines) > 300:
            del log_lines[: len(log_lines) - 300]

    def append_console_bytes(data: bytes) -> None:
        if not data:
            return
        for b in data:
            if b == 0x0A:
                console_lines.append("")
            elif b == 0x0D:
                continue
            elif b == 0x08:
                if console_lines and console_lines[-1]:
                    console_lines[-1] = console_lines[-1][:-1]
            elif 0x20 <= b <= 0x7E or b == 0x09:
                console_lines[-1] += chr(b)
            else:
                console_lines[-1] += "."

        if len(console_lines) > 1200:
            del console_lines[: len(console_lines) - 1200]

        if len(console_lines[-1]) > 400:
            console_lines.append("")

    def poll_stream() -> None:
        demux.poll()
        append_console_bytes(demux.pop_console_bytes())

    def send_raw(data: bytes) -> None:
        if not data:
            return
        ser.write(data)
        ser.flush()

    def do(cmd: int, payload: bytes = b"", retries: int = 3, timeout_override: float | None = None) -> Frame:
        nonlocal seq

        timeout_cmd = timeout_s if timeout_override is None else timeout_override
        frame = build_frame(seq, cmd, payload)
        last_exc: Exception | None = None

        for attempt in range(max(1, retries)):
            try:
                if tx_byte_delay_s > 0.0:
                    for b in frame:
                        ser.write(bytes([b]))
                        ser.flush()
                        if tx_byte_delay_s > 0:
                            time.sleep(tx_byte_delay_s)
                else:
                    ser.write(frame)
                    ser.flush()

                deadline = time.time() + timeout_cmd
                while time.time() < deadline:
                    poll_stream()
                    got = demux.pop_frame_for_seq(seq)
                    if got is not None:
                        seq = (seq + 1) & 0xFF
                        return got
                    time.sleep(0.002)
                raise TimeoutError("timed out waiting for response")
            except Exception as exc:  # noqa: BLE001
                last_exc = exc
                if attempt + 1 < retries:
                    add_log(f"retry cmd=0x{cmd:02x}: {exc}")
                    continue
                break

        if last_exc is not None:
            raise last_exc
        raise TimeoutError("command retries exhausted")

    def expect_ok(resp: Frame, context: str) -> None:
        if resp.status != 0:
            raise RuntimeError(f"{context}: {status_name(resp.status)}")

    def read_status_fast() -> dict[str, int]:
        resp = do(CMD_READ_STATUS, retries=1, timeout_override=min(timeout_s, 0.35))
        expect_ok(resp, "status")
        st = parse_status_payload(resp.payload)
        if not st:
            raise RuntimeError("status payload parse error")
        return st

    def ensure_halted() -> dict[str, int]:
        st = read_status_fast()
        if st.get("halted", 0):
            return st
        expect_ok(do(CMD_HALT, retries=2), "halt")
        deadline = time.time() + max(0.5, timeout_s)
        while time.time() < deadline:
            st = read_status_fast()
            if st.get("halted", 0):
                return st
            time.sleep(0.02)
        raise RuntimeError("timeout waiting for halted state")

    def mem_read_word(addr: int) -> int:
        resp = do(CMD_READ_MEM, struct.pack(">IB", addr & 0xFFFFFFFF, 2))
        expect_ok(resp, "mem-read")
        if len(resp.payload) != 4:
            raise RuntimeError(f"mem-read payload size {len(resp.payload)}")
        return int.from_bytes(resp.payload, "big")

    def mem_write_word(addr: int, value: int) -> None:
        resp = do(CMD_WRITE_MEM, struct.pack(">IBI", addr & 0xFFFFFFFF, 2, value & 0xFFFFFFFF))
        expect_ok(resp, "mem-write")

    def set_breakpoint(addr: int) -> None:
        if addr & 0x3:
            raise RuntimeError("breakpoint address must be word-aligned")
        if addr in breakpoints:
            add_log(f"breakpoint already set at 0x{addr:08x}")
            return
        ensure_halted()
        original = mem_read_word(addr)
        mem_write_word(addr, HALT_OPCODE)
        breakpoints[addr] = original
        add_log(f"bp set @0x{addr:08x} (orig=0x{original:08x})")

    def remove_breakpoint(addr: int) -> None:
        if addr not in breakpoints:
            add_log(f"no breakpoint at 0x{addr:08x}")
            return
        ensure_halted()
        original = breakpoints.pop(addr)
        mem_write_word(addr, original)
        add_log(f"bp removed @0x{addr:08x} (restored 0x{original:08x})")

    def clear_breakpoints() -> None:
        if not breakpoints:
            add_log("no breakpoints to clear")
            return
        ensure_halted()
        for addr in sorted(list(breakpoints.keys())):
            original = breakpoints.pop(addr)
            mem_write_word(addr, original)
            add_log(f"bp removed @0x{addr:08x}")

    def parse_u32(token: str) -> int:
        return int(token, 0) & 0xFFFFFFFF

    def cmd_help() -> list[str]:
        return [
            "help",
            "quit",
            "halt | resume | step | status",
            "pc set <addr>",
            "bp                (toggle at current PC)",
            "bp add <addr>",
            "bp del <addr>",
            "bp list",
            "bp clear",
            "send <text>       (send one console line)",
        ]

    def handle_command(line: str) -> bool:
        nonlocal last_status, last_err
        if not line.strip():
            return False

        try:
            toks = shlex.split(line)
        except Exception as exc:  # noqa: BLE001
            last_err = str(exc)
            add_log(f"cmd parse err: {exc}")
            return False

        if not toks:
            return False

        cmd = toks[0].lower()

        try:
            if cmd in ("q", "quit", "exit"):
                return True

            if cmd in ("help", "?"):
                for ent in cmd_help():
                    add_log(ent)
                return False

            if cmd == "halt":
                expect_ok(do(CMD_HALT), "halt")
                add_log("halt requested")
                return False

            if cmd == "resume":
                expect_ok(do(CMD_RESUME), "resume")
                add_log("resume requested")
                return False

            if cmd == "step":
                expect_ok(do(CMD_STEP), "step")
                add_log("step requested")
                return False

            if cmd == "status":
                st = read_status_fast()
                last_status = st
                add_log(
                    f"status halted={st['halted']} reason={halt_reason_name(st['halt_reason'])} "
                    f"pc=0x{st['pc']:08x} fault={st['last_fault']}"
                )
                return False

            if cmd in ("pc", "setpc"):
                if cmd == "setpc":
                    if len(toks) != 2:
                        raise RuntimeError("setpc usage: setpc <addr>")
                    addr_tok = toks[1]
                else:
                    if len(toks) != 3 or toks[1].lower() != "set":
                        raise RuntimeError("pc usage: pc set <addr>")
                    addr_tok = toks[2]

                addr = parse_u32(addr_tok)
                ensure_halted()
                expect_ok(do(CMD_SET_PC, struct.pack(">I", addr)), "pc-set")
                add_log(f"pc set -> 0x{addr & 0xFFFFFFFC:08x}")
                return False

            if cmd == "send":
                text = line[len(toks[0]) :].lstrip()
                send_raw(text.encode("utf-8", errors="replace") + b"\n")
                add_log(f"tx console {len(text) + 1} byte(s)")
                return False

            if cmd in ("bp", "break"):
                if len(toks) == 1:
                    st = ensure_halted()
                    addr = st["pc"]
                    if addr in breakpoints:
                        remove_breakpoint(addr)
                    else:
                        set_breakpoint(addr)
                    return False

                sub = toks[1].lower()
                if sub in ("list", "ls"):
                    if not breakpoints:
                        add_log("bp: none")
                    else:
                        for addr in sorted(breakpoints.keys()):
                            add_log(f"bp @0x{addr:08x} -> 0x{breakpoints[addr]:08x}")
                    return False

                if sub in ("add", "set") and len(toks) == 3:
                    set_breakpoint(parse_u32(toks[2]))
                    return False

                if sub in ("del", "rm", "remove") and len(toks) == 3:
                    remove_breakpoint(parse_u32(toks[2]))
                    return False

                if sub in ("clear", "clr"):
                    clear_breakpoints()
                    return False

                raise RuntimeError("bp usage: bp [add|del|list|clear] [addr]")

            raise RuntimeError(f"unknown command: {cmd}")
        except Exception as exc:  # noqa: BLE001
            last_err = str(exc)
            add_log(f"cmd err: {exc}")
            return False

    def draw_line(stdscr, y: int, x: int, text: str, width: int) -> None:
        if y < 0:
            return
        try:
            stdscr.addnstr(y, x, text, max(0, width))
        except Exception:
            return

    def draw(stdscr) -> int:
        nonlocal last_status, last_err, last_update, input_mode, input_buf

        stdscr.nodelay(True)
        stdscr.timeout(20)
        curses.curs_set(0)

        add_log("ncdb TUI started")
        add_log("Ctrl-A toggles console/cmd input mode; type 'help' in cmd mode")

        while True:
            poll_stream()

            now = time.time()
            if now - last_update > 0.25:
                try:
                    last_status = read_status_fast()
                    last_err = ""
                except Exception as exc:  # noqa: BLE001
                    last_err = str(exc)
                last_update = now

            h, w = stdscr.getmaxyx()
            stdscr.erase()

            st = last_status
            halted = st.get("halted", 0)
            reason = halt_reason_name(st.get("halt_reason", 0))
            pc = st.get("pc", 0)

            bp_keys = sorted(breakpoints.keys())
            bp_preview = " ".join(f"0x{a:08x}" for a in bp_keys[:4])
            if len(bp_keys) > 4:
                bp_preview += " ..."

            draw_line(stdscr, 0, 0, "ncdb tui | integrated console + debug", w - 1)
            draw_line(
                stdscr,
                1,
                0,
                f"halted={halted} reason={reason} pc=0x{pc:08x} fault={st.get('last_fault', 0)}",
                w - 1,
            )
            draw_line(
                stdscr,
                2,
                0,
                f"fault_pc=0x{st.get('fault_pc', 0):08x} fault_addr=0x{st.get('fault_addr', 0):08x}",
                w - 1,
            )
            draw_line(stdscr, 3, 0, f"breakpoints({len(bp_keys)}): {bp_preview}", w - 1)
            draw_line(stdscr, 4, 0, "console mode: Enter sends line | cmd mode: Enter runs command", w - 1)

            input_rows = 2
            log_rows = 4
            console_y0 = 6
            console_y1 = max(console_y0, h - input_rows - log_rows - 1)
            console_rows = max(1, console_y1 - console_y0 + 1)

            draw_line(stdscr, 5, 0, "-" * max(0, w - 1), w - 1)

            console_tail = console_lines[-console_rows:]
            for i, ln in enumerate(console_tail):
                draw_line(stdscr, console_y0 + i, 0, ln, w - 1)

            log_y0 = console_y1 + 1
            draw_line(stdscr, log_y0, 0, "-" * max(0, w - 1), w - 1)
            recent_logs = log_lines[-(log_rows - 1) :]
            for i, ln in enumerate(recent_logs):
                draw_line(stdscr, log_y0 + 1 + i, 0, ln, w - 1)

            input_prompt = "cmd> " if input_mode == "cmd" else "tx> "
            draw_line(stdscr, h - 2, 0, input_prompt + input_buf, w - 1)
            draw_line(
                stdscr,
                h - 1,
                0,
                "Ctrl-A mode toggle | cmd: quit/help/halt/resume/step/status/bp ... | err: " + last_err,
                w - 1,
            )

            stdscr.refresh()

            ch = stdscr.getch()
            if ch == -1:
                continue

            if ch == 1:  # Ctrl-A
                input_mode = "cmd" if input_mode == "console" else "console"
                continue

            if ch in (27,):  # ESC
                input_mode = "console"
                continue

            if ch in (curses.KEY_BACKSPACE, 127, 8):
                if input_buf:
                    input_buf = input_buf[:-1]
                continue

            if ch in (10, 13):
                line = input_buf
                input_buf = ""

                if input_mode == "console":
                    if line:
                        send_raw(line.encode("utf-8", errors="replace") + b"\n")
                        add_log(f"tx console {len(line) + 1} byte(s)")
                else:
                    should_quit = handle_command(line)
                    if should_quit:
                        try:
                            clear_breakpoints()
                        except Exception as exc:  # noqa: BLE001
                            add_log(f"bp restore warning: {exc}")
                        return 0
                continue

            if 32 <= ch <= 126:
                input_buf += chr(ch)

    try:
        return curses.wrapper(draw)
    finally:
        ser.timeout = old_timeout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="Serial device path")
    parser.add_argument("--baud", type=int, default=1000000)
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument(
        "--tx-byte-delay-ms",
        type=float,
        default=1.0,
        help="Delay between transmitted frame bytes in milliseconds (default: 1.0)",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("hello")
    sub.add_parser("halt")
    sub.add_parser("resume")
    sub.add_parser("step")
    p_pc_set = sub.add_parser("pc-set")
    p_pc_set.add_argument("addr", type=lambda x: int(x, 0))
    sub.add_parser("status")
    sub.add_parser("counters")
    sub.add_parser("tui")

    p_gpr_r = sub.add_parser("gpr-read")
    p_gpr_r.add_argument("idx", type=int)

    p_gpr_w = sub.add_parser("gpr-write")
    p_gpr_w.add_argument("idx", type=int)
    p_gpr_w.add_argument("value", type=lambda x: int(x, 0))

    p_mem_r = sub.add_parser("mem-read")
    p_mem_r.add_argument("addr", type=lambda x: int(x, 0))
    p_mem_r.add_argument("size", type=int, choices=[1, 2, 4], default=4)

    p_mem_w = sub.add_parser("mem-write")
    p_mem_w.add_argument("addr", type=lambda x: int(x, 0))
    p_mem_w.add_argument("size", type=int, choices=[1, 2, 4], default=4)
    p_mem_w.add_argument("value", type=lambda x: int(x, 0))

    p_mem_rb = sub.add_parser("mem-read-burst")
    p_mem_rb.add_argument("addr", type=lambda x: int(x, 0))
    p_mem_rb.add_argument("size", type=int, choices=[1, 2, 4], default=4)
    p_mem_rb.add_argument("count", type=positive_int)

    p_mem_sb = sub.add_parser("mem-set-burst")
    p_mem_sb.add_argument("addr", type=lambda x: int(x, 0))
    p_mem_sb.add_argument("size", type=int, choices=[1, 2, 4], default=4)
    p_mem_sb.add_argument("value", type=lambda x: int(x, 0))
    p_mem_sb.add_argument("count", type=positive_int)

    p_listen = sub.add_parser("listen")
    p_listen.add_argument("--seconds", type=float, default=3.0)

    args = parser.parse_args()

    try:
        import serial  # type: ignore
    except Exception as exc:
        print(f"pyserial is required: {exc}", file=sys.stderr)
        return 2

    with serial.Serial(args.port, args.baud, timeout=0.05) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        tx_byte_delay_s = max(0.0, args.tx_byte_delay_ms) / 1000.0

        if args.cmd == "listen":
            data = sniff_bytes(ser, args.seconds)
            print(f"rx_bytes={len(data)}")
            if data:
                print(f"hex={data.hex()}")
                print(f"ascii={data.decode('ascii', errors='replace')!r}")
            return 0

        if args.cmd == "tui":
            return run_tui(ser, args.timeout, tx_byte_delay_s)

        seq = 1

        def do(cmd: int, payload: bytes = b"") -> Frame:
            nonlocal seq
            resp = send_cmd_retry(
                ser,
                seq,
                cmd,
                payload,
                args.timeout,
                retries=4,
                tx_byte_delay_s=tx_byte_delay_s,
            )
            seq = (seq + 1) & 0xFF
            return resp

        def do_mem_read(addr: int, size: int) -> int:
            size_code = mem_size_code(size)
            read_resp = do(CMD_READ_MEM, struct.pack(">IB", addr & 0xFFFFFFFF, size_code))
            if read_resp.status != 0:
                raise RuntimeError(f"mem-read 0x{addr & 0xFFFFFFFF:08x}: {status_name(read_resp.status)}")
            if len(read_resp.payload) != 4:
                raise RuntimeError(f"mem-read payload size {len(read_resp.payload)}")
            return int.from_bytes(read_resp.payload, "big")

        def do_mem_write(addr: int, size: int, value: int) -> None:
            size_code = mem_size_code(size)
            write_resp = do(
                CMD_WRITE_MEM,
                struct.pack(">IBI", addr & 0xFFFFFFFF, size_code, value & 0xFFFFFFFF),
            )
            if write_resp.status != 0:
                raise RuntimeError(f"mem-write 0x{addr & 0xFFFFFFFF:08x}: {status_name(write_resp.status)}")

        def do_mem_read_burst(addr: int, size: int, count: int) -> list[int]:
            size_code = mem_size_code(size)
            out: list[int] = []
            remaining = count
            cur_addr = addr & 0xFFFFFFFF
            while remaining > 0:
                chunk = min(remaining, MAX_READ_BURST_WORDS)
                resp_burst = do(CMD_READ_MEM_BURST, struct.pack(">IBB", cur_addr, size_code, chunk))
                if resp_burst.status != 0:
                    raise RuntimeError(f"mem-read-burst 0x{cur_addr:08x}: {status_name(resp_burst.status)}")
                expected = chunk * 4
                if len(resp_burst.payload) != expected:
                    raise RuntimeError(
                        f"mem-read-burst payload size {len(resp_burst.payload)} (expected {expected})"
                    )
                out.extend(unpack_words(resp_burst.payload))
                cur_addr = (cur_addr + (chunk * size)) & 0xFFFFFFFF
                remaining -= chunk
            return out

        def do_mem_set_burst(addr: int, size: int, value: int, count: int) -> None:
            size_code = mem_size_code(size)
            value_mask = (1 << (8 * size)) - 1
            set_value = value & value_mask
            remaining = count
            cur_addr = addr & 0xFFFFFFFF
            while remaining > 0:
                chunk = min(remaining, MAX_SET_BURST_COUNT)
                resp_burst = do(CMD_SET_MEM_BURST, struct.pack(">IBBI", cur_addr, size_code, chunk, set_value))
                if resp_burst.status != 0:
                    raise RuntimeError(f"mem-set-burst 0x{cur_addr:08x}: {status_name(resp_burst.status)}")
                if resp_burst.payload:
                    raise RuntimeError(f"mem-set-burst unexpected payload ({len(resp_burst.payload)} bytes)")
                cur_addr = (cur_addr + (chunk * size)) & 0xFFFFFFFF
                remaining -= chunk

        if args.cmd == "hello":
            resp = do(CMD_HELLO)
        elif args.cmd == "halt":
            resp = do(CMD_HALT)
        elif args.cmd == "resume":
            resp = do(CMD_RESUME)
        elif args.cmd == "step":
            resp = do(CMD_STEP)
        elif args.cmd == "pc-set":
            resp = do(CMD_SET_PC, struct.pack(">I", args.addr & 0xFFFFFFFF))
        elif args.cmd == "status":
            resp = do(CMD_READ_STATUS)
        elif args.cmd == "counters":
            resp = do(CMD_READ_COUNTERS)
        elif args.cmd == "gpr-read":
            resp = do(CMD_READ_GPR, bytes([args.idx & 0x0F]))
        elif args.cmd == "gpr-write":
            resp = do(CMD_WRITE_GPR, bytes([args.idx & 0x0F]) + struct.pack(">I", args.value & 0xFFFFFFFF))
        elif args.cmd == "mem-read":
            resp = do(CMD_READ_MEM, struct.pack(">IB", args.addr & 0xFFFFFFFF, mem_size_code(args.size)))
        elif args.cmd == "mem-write":
            resp = do(CMD_WRITE_MEM, struct.pack(">IBI", args.addr & 0xFFFFFFFF, mem_size_code(args.size), args.value & 0xFFFFFFFF))
        elif args.cmd == "mem-read-burst":
            stride = args.size
            width = args.size * 2
            words = do_mem_read_burst(args.addr, args.size, args.count)
            print(f"status=OK burst=read size={args.size} count={args.count}")
            for i, raw in enumerate(words):
                addr = (args.addr + (i * stride)) & 0xFFFFFFFF
                value = raw & ((1 << (8 * args.size)) - 1)
                print(f"  [{i:04d}] addr=0x{addr:08x} value=0x{value:0{width}x} raw=0x{raw:08x}")
            return 0
        elif args.cmd == "mem-set-burst":
            stride = args.size
            width = args.size * 2
            value_mask = (1 << (8 * args.size)) - 1
            value = args.value & value_mask
            do_mem_set_burst(args.addr, args.size, value, args.count)
            print(
                f"status=OK burst=set size={args.size} count={args.count} "
                f"value=0x{value:0{width}x}"
            )
            for i in range(args.count):
                addr = (args.addr + (i * stride)) & 0xFFFFFFFF
                print(f"  [{i:04d}] addr=0x{addr:08x} value=0x{value:0{width}x}")
            return 0
        else:
            raise AssertionError("unreachable")

    status_text = status_name(resp.status)
    print(f"status={status_text} payload_len={len(resp.payload)}")
    if resp.payload:
        words = unpack_words(resp.payload)
        if words:
            print("words:")
            for i, w in enumerate(words):
                print(f"  [{i}] 0x{w:08x}")
        print(f"payload_hex={resp.payload.hex()}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
