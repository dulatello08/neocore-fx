#!/usr/bin/env python3
"""Extract core_any profile metrics from simulation stdout into JSON."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


PATTERNS = {
    "halt_pc": re.compile(r"Program halted at PC = 0x([0-9a-fA-F]+)"),
    "cycles": re.compile(r"Total cycles:\s*(\d+)"),
    "retired": re.compile(r"Retired instructions:\s*(\d+)"),
    "ipc": re.compile(r"IPC \(retired\):\s*([0-9]+\.[0-9]+)"),
    "redirects": re.compile(r"Redirect count:\s*(\d+)"),
    "load_stalls": re.compile(r"Load-use stall cycles:\s*(\d+)"),
    "mem_stalls": re.compile(r"Memory wait stall cycles:\s*(\d+)"),
    "wb_fault": re.compile(r"WB fault seen:\s*(\d+)"),
}


def parse_metrics(text: str) -> dict[str, int | float | str]:
    out: dict[str, int | float | str] = {}
    for key, pattern in PATTERNS.items():
        m = pattern.search(text)
        if not m:
            continue
        raw = m.group(1)
        if key in {"ipc"}:
            out[key] = float(raw)
        elif key in {"halt_pc"}:
            out[key] = f"0x{raw.lower()}"
        else:
            out[key] = int(raw)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Simulation log text file")
    parser.add_argument("--out", type=Path, default=None, help="Optional JSON output path")
    args = parser.parse_args()

    text = args.input.read_text(encoding="utf-8")
    metrics = parse_metrics(text)

    if args.out is None:
        print(json.dumps(metrics, indent=2, sort_keys=True))
    else:
        args.out.write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Wrote metrics JSON: {args.out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
