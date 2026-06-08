#!/usr/bin/env python3
"""Convert binary blobs to byte-per-line hex for tb_core_any."""

from __future__ import annotations

import argparse
from pathlib import Path


def convert(in_path: Path, out_path: Path) -> int:
    data = in_path.read_bytes()
    lines = [f"{b:02X}" for b in data]
    out_path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    return len(data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Input binary file")
    parser.add_argument("output", type=Path, help="Output byte-hex file")
    args = parser.parse_args()

    count = convert(args.input, args.output)
    print(f"Wrote {count} bytes to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
