#!/usr/bin/env python3
"""Build and run tb_core_any with program/profile/debug options."""

from __future__ import annotations

import argparse
import shlex
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SIM_HELPER = ROOT / "scripts" / "sim.py"
FILELIST = ROOT / "filelists" / "sim_core_any.f"
BUILD_DIR = ROOT / "build" / "sim_core_any"
SIM_BIN = BUILD_DIR / "tb_core_any_simv"


def run(cmd: list[str]) -> None:
    print("$", " ".join(shlex.quote(x) for x in cmd))
    subprocess.run(cmd, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--program", default="mem/test_smoke.hex", help="Byte-hex program path")
    parser.add_argument("--debug", action="store_true", help="Enable +DEBUG")
    parser.add_argument("--profile", action="store_true", help="Enable +PROFILE")
    parser.add_argument("--waves", action="store_true", help="Enable +WAVES")
    parser.add_argument("--max-cycles", type=int, default=0, help="Optional +MAX_CYCLES override")
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--flags", default="-g2012 -Wall -Winfloop")
    args = parser.parse_args()

    program = Path(args.program)
    if not program.is_absolute():
        program = (ROOT / program).resolve()
    if not program.exists():
        raise FileNotFoundError(f"program not found: {program}")

    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    run(
        [
            "python3",
            str(SIM_HELPER),
            "build",
            "--filelist",
            str(FILELIST),
            "--out",
            str(SIM_BIN),
            "--top",
            "tb_core_any",
            "--iverilog",
            args.iverilog,
            "--flags",
            args.flags,
            "--build-dir",
            str(BUILD_DIR),
        ]
    )

    plusargs = [f"+PROGRAM={program}"]
    if args.debug:
        plusargs.append("+DEBUG")
    if args.profile:
        plusargs.append("+PROFILE")
    if args.max_cycles > 0:
        plusargs.append(f"+MAX_CYCLES={args.max_cycles}")

    cmd = [
        "python3",
        str(SIM_HELPER),
        "run",
        "--sim",
        str(SIM_BIN),
        "--vvp",
        args.vvp,
        "--vvp-args",
        " ".join(plusargs),
    ]
    if args.waves:
        cmd.extend(["--plusarg", "WAVES"])

    run(cmd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
