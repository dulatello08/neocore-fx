"""Curses TUI for ncdb."""

from __future__ import annotations

import shlex
import struct
import sys
import time

from .protocol import (
    CMD_HALT,
    CMD_READ_MEM,
    CMD_READ_STATUS,
    CMD_RESUME,
    CMD_SET_PC,
    CMD_STEP,
    CMD_WRITE_MEM,
    Frame,
    HALT_OPCODE,
    StreamDemux,
    build_frame,
    halt_reason_name,
    parse_status_payload,
    status_name,
)
from .tui_support import add_log, append_console_bytes, cmd_help, parse_u32, render_screen

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

    def poll_stream() -> None:
        demux.poll()
        append_console_bytes(console_lines, demux.pop_console_bytes())

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
                    add_log(log_lines, f"retry cmd=0x{cmd:02x}: {exc}")
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
            add_log(log_lines, f"breakpoint already set at 0x{addr:08x}")
            return
        ensure_halted()
        original = mem_read_word(addr)
        mem_write_word(addr, HALT_OPCODE)
        breakpoints[addr] = original
        add_log(log_lines, f"bp set @0x{addr:08x} (orig=0x{original:08x})")

    def remove_breakpoint(addr: int) -> None:
        if addr not in breakpoints:
            add_log(log_lines, f"no breakpoint at 0x{addr:08x}")
            return
        ensure_halted()
        original = breakpoints.pop(addr)
        mem_write_word(addr, original)
        add_log(log_lines, f"bp removed @0x{addr:08x} (restored 0x{original:08x})")

    def clear_breakpoints() -> None:
        if not breakpoints:
            add_log(log_lines, "no breakpoints to clear")
            return
        ensure_halted()
        for addr in sorted(list(breakpoints.keys())):
            original = breakpoints.pop(addr)
            mem_write_word(addr, original)
            add_log(log_lines, f"bp removed @0x{addr:08x}")

    def handle_command(line: str) -> bool:
        nonlocal last_status, last_err
        if not line.strip():
            return False

        try:
            toks = shlex.split(line)
        except Exception as exc:  # noqa: BLE001
            last_err = str(exc)
            add_log(log_lines, f"cmd parse err: {exc}")
            return False

        if not toks:
            return False

        cmd = toks[0].lower()

        try:
            if cmd in ("q", "quit", "exit"):
                return True

            if cmd in ("help", "?"):
                for ent in cmd_help():
                    add_log(log_lines, ent)
                return False

            if cmd == "halt":
                expect_ok(do(CMD_HALT), "halt")
                add_log(log_lines, "halt requested")
                return False

            if cmd == "resume":
                expect_ok(do(CMD_RESUME), "resume")
                add_log(log_lines, "resume requested")
                return False

            if cmd == "step":
                expect_ok(do(CMD_STEP), "step")
                add_log(log_lines, "step requested")
                return False

            if cmd == "status":
                st = read_status_fast()
                last_status = st
                add_log(
                    log_lines,
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
                add_log(log_lines, f"pc set -> 0x{addr & 0xFFFFFFFC:08x}")
                return False

            if cmd == "send":
                text = line[len(toks[0]) :].lstrip()
                send_raw(text.encode("utf-8", errors="replace") + b"\n")
                add_log(log_lines, f"tx console {len(text) + 1} byte(s)")
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
                        add_log(log_lines, "bp: none")
                    else:
                        for addr in sorted(breakpoints.keys()):
                            add_log(log_lines, f"bp @0x{addr:08x} -> 0x{breakpoints[addr]:08x}")
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
            add_log(log_lines, f"cmd err: {exc}")
            return False

    def draw(stdscr) -> int:
        nonlocal last_status, last_err, last_update, input_mode, input_buf

        stdscr.nodelay(True)
        stdscr.timeout(20)
        curses.curs_set(0)

        add_log(log_lines, "ncdb TUI started")
        add_log(log_lines, "Ctrl-A toggles console/cmd input mode; type 'help' in cmd mode")

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

            render_screen(
                stdscr,
                last_status,
                breakpoints,
                console_lines,
                log_lines,
                input_mode,
                input_buf,
                last_err,
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
                        add_log(log_lines, f"tx console {len(line) + 1} byte(s)")
                else:
                    should_quit = handle_command(line)
                    if should_quit:
                        try:
                            clear_breakpoints()
                        except Exception as exc:  # noqa: BLE001
                            add_log(log_lines, f"bp restore warning: {exc}")
                        return 0
                continue

            if 32 <= ch <= 126:
                input_buf += chr(ch)

    try:
        return curses.wrapper(draw)
    finally:
        ser.timeout = old_timeout
