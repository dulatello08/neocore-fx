#!/usr/bin/env python3
"""Convert byte-per-line hex into word-per-line (32-bit) hex."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_byte(token: str) -> int:
    t = token.strip().replace("_", "")
    if t.startswith(("0x", "0X")):
        t = t[2:]
    if not t:
        raise ValueError("empty byte token")
    value = int(t, 16)
    if value < 0 or value > 0xFF:
        raise ValueError(f"byte out of range: {token}")
    return value


def convert(in_path: Path, out_path: Path, depth: int) -> tuple[int, int]:
    bytes_in: list[int] = []
    for raw in in_path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        bytes_in.append(parse_byte(line))

    words: list[int] = []
    for i in range(0, len(bytes_in), 4):
        b0 = bytes_in[i]
        b1 = bytes_in[i + 1] if (i + 1) < len(bytes_in) else 0
        b2 = bytes_in[i + 2] if (i + 2) < len(bytes_in) else 0
        b3 = bytes_in[i + 3] if (i + 3) < len(bytes_in) else 0
        words.append((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)

    if len(words) > depth:
        raise ValueError(f"input has {len(words)} words, exceeds depth {depth}")

    if len(words) < depth:
        words.extend([0] * (depth - len(words)))

    out_lines = [f"{w:08x}" for w in words]
    out_path.write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    return len(bytes_in), len(words)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Input byte-hex file")
    parser.add_argument("output", type=Path, help="Output word-hex file")
    parser.add_argument("--depth", type=int, default=16384, help="Output word depth (default: 16384)")
    args = parser.parse_args()

    byte_count, word_count = convert(args.input, args.output, args.depth)
    print(f"Converted {byte_count} bytes -> {word_count} words into {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
