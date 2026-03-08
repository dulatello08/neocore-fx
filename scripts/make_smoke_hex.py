#!/usr/bin/env python3
"""Generate the canonical NeoCoreFX smoke byte-hex image."""

from __future__ import annotations

import argparse
from pathlib import Path


WORDS = [
    0x1010_0005,  # ADDI 1, 0, 5
    0x1021_0007,  # ADDI 2, 1, 7
    0x0131_2000,  # ADD  3, 1, 2
    0x0243_1000,  # SUB  4, 3, 1
    0x4000_0000,  # B .
]


def write_hex(path: Path) -> None:
    lines: list[str] = []
    for word in WORDS:
        lines.extend(
            [
                f"{(word >> 24) & 0xFF:02X}",
                f"{(word >> 16) & 0xFF:02X}",
                f"{(word >> 8) & 0xFF:02X}",
                f"{word & 0xFF:02X}",
            ]
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("mem/test_smoke.hex"))
    args = parser.parse_args()

    write_hex(args.out)
    print(f"Wrote {args.out} ({len(WORDS) * 4} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
