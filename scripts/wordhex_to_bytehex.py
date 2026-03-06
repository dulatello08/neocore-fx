#!/usr/bin/env python3
"""Convert word-per-line hex (32-bit) into byte-per-line big-endian hex."""

from __future__ import annotations

import argparse
from pathlib import Path


def normalize_word(token: str) -> int:
    token = token.strip().replace("_", "")
    if token.startswith("0x") or token.startswith("0X"):
        token = token[2:]
    if not token:
        raise ValueError("empty token")
    value = int(token, 16)
    if value < 0 or value > 0xFFFF_FFFF:
        raise ValueError(f"word out of range: {token}")
    return value


def convert(in_path: Path, out_path: Path) -> tuple[int, int]:
    word_count = 0
    byte_lines: list[str] = []

    for raw in in_path.read_text(encoding="utf-8").splitlines():
      line = raw.split("#", 1)[0].strip()
      if not line:
        continue
      value = normalize_word(line)
      byte_lines.extend(
          [
              f"{(value >> 24) & 0xFF:02X}",
              f"{(value >> 16) & 0xFF:02X}",
              f"{(value >> 8) & 0xFF:02X}",
              f"{value & 0xFF:02X}",
          ]
      )
      word_count += 1

    out_path.write_text("\n".join(byte_lines) + ("\n" if byte_lines else ""), encoding="utf-8")
    return word_count, len(byte_lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Input word-hex file")
    parser.add_argument("output", type=Path, help="Output byte-hex file")
    args = parser.parse_args()

    words, bytes_written = convert(args.input, args.output)
    print(f"Converted {words} words -> {bytes_written} bytes into {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
