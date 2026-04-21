#!/usr/bin/env python3
"""ncdb - NeoCoreFX hardware debug client."""

from __future__ import annotations

import argparse
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
CMD_READ_STATUS = 0x20
CMD_READ_GPR = 0x21
CMD_WRITE_GPR = 0x22
CMD_READ_MEM = 0x23
CMD_WRITE_MEM = 0x24
CMD_READ_COUNTERS = 0x25

STATUS_NAMES = {
    0x00: "OK",
    0x01: "CRC_ERR",
    0x02: "BAD_CMD",
    0x03: "BUS_ERR",
    0x04: "BUSY",
    0x05: "NOT_HALTED",
    0x06: "TIMEOUT",
}


@dataclass
class Frame:
    seq: int
    status: int
    payload: bytes


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


def run_tui(ser, timeout_s: float, tx_byte_delay_s: float) -> int:
    try:
        import curses
    except Exception as exc:
        print(f"tui mode requires curses: {exc}", file=sys.stderr)
        return 2

    seq = 1

    def do(cmd: int, payload: bytes = b"") -> Frame:
        nonlocal seq
        resp = send_cmd_retry(
            ser,
            seq,
            cmd,
            payload,
            timeout_s,
            retries=4,
            tx_byte_delay_s=tx_byte_delay_s,
        )
        seq = (seq + 1) & 0xFF
        return resp

    def draw(stdscr) -> int:
        stdscr.nodelay(True)
        stdscr.timeout(120)
        curses.curs_set(0)

        last_status = "-"
        last_err = ""
        last_update = 0.0

        while True:
            now = time.time()
            if now - last_update > 0.25:
                try:
                    resp = do(CMD_READ_STATUS)
                    if resp.status == 0:
                        st = parse_status_payload(resp.payload)
                        if st:
                            last_status = (
                                f"halted={st['halted']} reason={st['halt_reason']} fault={st['last_fault']} "
                                f"pc=0x{st['pc']:08x} fault_pc=0x{st['fault_pc']:08x}"
                            )
                        else:
                            last_status = "status payload parse error"
                        last_err = ""
                    else:
                        name = STATUS_NAMES.get(resp.status, f"0x{resp.status:02x}")
                        last_err = f"status={name}"
                except Exception as exc:  # noqa: BLE001
                    last_err = str(exc)
                last_update = now

            stdscr.erase()
            stdscr.addstr(0, 0, "ncdb tui")
            stdscr.addstr(2, 0, "Keys: h=halt  r=resume  s=step  q=quit")
            stdscr.addstr(4, 0, f"{last_status[:120]}")
            if last_err:
                stdscr.addstr(6, 0, f"err: {last_err[:120]}")
            stdscr.refresh()

            ch = stdscr.getch()
            if ch == -1:
                continue
            if ch in (ord("q"), ord("Q")):
                return 0
            if ch in (ord("h"), ord("H")):
                try:
                    do(CMD_HALT)
                except Exception as exc:  # noqa: BLE001
                    last_err = str(exc)
            if ch in (ord("r"), ord("R")):
                try:
                    do(CMD_RESUME)
                except Exception as exc:  # noqa: BLE001
                    last_err = str(exc)
            if ch in (ord("s"), ord("S")):
                try:
                    do(CMD_STEP)
                except Exception as exc:  # noqa: BLE001
                    last_err = str(exc)

    return curses.wrapper(draw)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="Serial device path")
    parser.add_argument("--baud", type=int, default=115200)
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

        if args.cmd == "hello":
            resp = do(CMD_HELLO)
        elif args.cmd == "halt":
            resp = do(CMD_HALT)
        elif args.cmd == "resume":
            resp = do(CMD_RESUME)
        elif args.cmd == "step":
            resp = do(CMD_STEP)
        elif args.cmd == "status":
            resp = do(CMD_READ_STATUS)
        elif args.cmd == "counters":
            resp = do(CMD_READ_COUNTERS)
        elif args.cmd == "gpr-read":
            resp = do(CMD_READ_GPR, bytes([args.idx & 0x0F]))
        elif args.cmd == "gpr-write":
            resp = do(CMD_WRITE_GPR, bytes([args.idx & 0x0F]) + struct.pack(">I", args.value & 0xFFFFFFFF))
        elif args.cmd == "mem-read":
            size_code = {1: 0, 2: 1, 4: 2}[args.size]
            resp = do(CMD_READ_MEM, struct.pack(">IB", args.addr & 0xFFFFFFFF, size_code))
        elif args.cmd == "mem-write":
            size_code = {1: 0, 2: 1, 4: 2}[args.size]
            resp = do(
                CMD_WRITE_MEM,
                struct.pack(">IBI", args.addr & 0xFFFFFFFF, size_code, args.value & 0xFFFFFFFF),
            )
        else:
            raise AssertionError("unreachable")

    status_name = STATUS_NAMES.get(resp.status, f"0x{resp.status:02x}")
    print(f"status={status_name} payload_len={len(resp.payload)}")
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
