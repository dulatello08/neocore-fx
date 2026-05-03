"""Frame protocol helpers for ncdb."""

from __future__ import annotations

import argparse
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
