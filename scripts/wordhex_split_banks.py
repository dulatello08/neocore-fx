#!/usr/bin/env python3
"""Split word-per-line hex into four bank files (word index modulo 4)."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_word(token: str) -> str:
    t = token.strip().split("#", 1)[0].replace("_", "")
    if not t:
        return ""
    if t.startswith(("0x", "0X")):
        t = t[2:]
    value = int(t, 16)
    if value < 0 or value > 0xFFFF_FFFF:
        raise ValueError(f"word out of range: {token}")
    return f"{value:08x}"


def split_banks(in_path: Path, out_prefix: Path) -> tuple[int, int]:
    banks = [[], [], [], []]
    words = []
    for raw in in_path.read_text(encoding="utf-8").splitlines():
        w = parse_word(raw)
        if not w:
            continue
        words.append(w)

    for idx, word in enumerate(words):
        banks[idx & 0x3].append(word)

    for bank_idx, lines in enumerate(banks):
        out_path = Path(f"{out_prefix}.bank{bank_idx}.wordhex")
        out_path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")

    return len(words), len(banks[0])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Input word-hex file")
    parser.add_argument("out_prefix", type=Path, help="Output file prefix")
    args = parser.parse_args()

    total_words, bank_words = split_banks(args.input, args.out_prefix)
    print(f"Split {total_words} words into 4 banks, {bank_words} words/bank")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
