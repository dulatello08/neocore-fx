"""Command-line interface for ncdb."""

from __future__ import annotations

import argparse
import struct
import sys

from .protocol import (
    CMD_HALT,
    CMD_HELLO,
    CMD_READ_COUNTERS,
    CMD_READ_GPR,
    CMD_READ_MEM,
    CMD_READ_MEM_BURST,
    CMD_READ_STATUS,
    CMD_RESUME,
    CMD_SET_MEM_BURST,
    CMD_SET_PC,
    CMD_STEP,
    CMD_WRITE_GPR,
    CMD_WRITE_MEM,
    Frame,
    MAX_READ_BURST_WORDS,
    MAX_SET_BURST_COUNT,
    mem_size_code,
    positive_int,
    send_cmd_retry,
    sniff_bytes,
    status_name,
    unpack_words,
)
from .tui import run_tui

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
