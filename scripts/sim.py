#!/usr/bin/env python3
"""NeoCoreFX build helper for simulation and FPGA flow."""

from __future__ import annotations

import argparse
import os
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Iterable, List, Set, Tuple


class Color:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"


USE_COLOR = sys.stdout.isatty() and os.getenv("NO_COLOR") is None


def style(text: str, *codes: str) -> str:
    if not USE_COLOR or not codes:
        return text
    return "".join(codes) + text + Color.RESET


def banner(title: str) -> None:
    line = "=" * 74
    print(style(line, Color.BOLD, Color.MAGENTA))
    print(style(f"  {title}", Color.BOLD, Color.MAGENTA))
    print(style(line, Color.BOLD, Color.MAGENTA))


def log(tag: str, msg: str, color: str) -> None:
    left = style(f"[{tag}]", Color.BOLD, color)
    print(f"{left} {msg}")


def info(msg: str) -> None:
    log("INFO", msg, Color.CYAN)


def step(msg: str) -> None:
    log("STEP", msg, Color.BLUE)


def ok(msg: str) -> None:
    log(" OK ", msg, Color.GREEN)


def warn(msg: str) -> None:
    log("WARN", msg, Color.YELLOW)


def _strip_comment(line: str) -> str:
    if "#" in line:
        line = line.split("#", 1)[0]
    return line.strip()


def _resolve_token(base_dir: Path, token: str) -> Path:
    path = Path(token)
    if not path.is_absolute():
        path = base_dir / path
    return path.resolve()


def parse_filelist(path: Path) -> Tuple[List[str], List[Path]]:
    seen_lists: Set[Path] = set()
    include_dirs: List[str] = []
    sources: List[Path] = []

    def _walk(list_path: Path) -> None:
        list_path = list_path.resolve()
        if list_path in seen_lists:
            return
        seen_lists.add(list_path)

        if not list_path.exists():
            raise FileNotFoundError(f"filelist not found: {list_path}")

        base_dir = list_path.parent
        for raw in list_path.read_text().splitlines():
            line = _strip_comment(raw)
            if not line:
                continue

            if line.startswith("-f "):
                nested = _resolve_token(base_dir, line.split(maxsplit=1)[1])
                _walk(nested)
                continue
            if line.startswith("-f") and len(line) > 2:
                nested = _resolve_token(base_dir, line[2:])
                _walk(nested)
                continue
            if line.startswith("+incdir+"):
                inc = _resolve_token(base_dir, line[len("+incdir+") :])
                include_dirs.append(f"+incdir+{inc}")
                continue

            src = _resolve_token(base_dir, line)
            if not src.exists():
                raise FileNotFoundError(f"source not found: {src}")
            sources.append(src)

    _walk(path)

    dedup_inc: List[str] = []
    seen_inc: Set[str] = set()
    for inc in include_dirs:
        if inc not in seen_inc:
            dedup_inc.append(inc)
            seen_inc.add(inc)

    dedup_src: List[Path] = []
    seen_src: Set[Path] = set()
    for src in sources:
        if src not in seen_src:
            dedup_src.append(src)
            seen_src.add(src)

    return dedup_inc, dedup_src


def write_resolved_filelist(path: Path, include_dirs: Iterable[str], sources: Iterable[Path]) -> None:
    lines = [*include_dirs, *(str(src) for src in sources)]
    path.write_text("\n".join(lines) + "\n")


def run_cmd(cmd: List[str], label: str) -> None:
    shown = " ".join(shlex.quote(x) for x in cmd)
    step(f"{label}")
    print(style(f"  $ {shown}", Color.YELLOW))
    start = time.perf_counter()
    subprocess.run(cmd, check=True)
    elapsed = time.perf_counter() - start
    ok(f"{label} done ({elapsed:.2f}s)")


def cmd_build(args: argparse.Namespace) -> int:
    banner("SIMULATION BUILD")
    filelist = Path(args.filelist).resolve()
    build_dir = Path(args.build_dir).resolve()
    out_path = Path(args.out).resolve()
    build_dir.mkdir(parents=True, exist_ok=True)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    incdirs, sources = parse_filelist(filelist)
    resolved = build_dir / "resolved_sim.f"
    write_resolved_filelist(resolved, incdirs, sources)
    info(f"filelist: {filelist}")
    info(f"resolved sources: {len(sources)}")
    info(f"top: {args.top}")
    info(f"output: {out_path}")

    flags = shlex.split(args.flags) if args.flags else []
    cmd = [args.iverilog, *flags, "-s", args.top, "-o", str(out_path), "-c", str(resolved)]
    run_cmd(cmd, "iverilog compile")
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    banner("SIMULATION RUN")
    sim = Path(args.sim).resolve()
    if not sim.exists():
        raise FileNotFoundError(f"simulation binary not found: {sim}")

    cmd = [args.vvp, str(sim)]
    if args.plusarg:
        info(f"plusarg: +{args.plusarg}")
        cmd.append(f"+{args.plusarg}")
    if args.vvp_args:
        cmd.extend(shlex.split(args.vvp_args))
    run_cmd(cmd, "vvp execute")
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    banner("RESOLVED SOURCES")
    filelist = Path(args.filelist).resolve()
    incdirs, sources = parse_filelist(filelist)
    info(f"filelist: {filelist}")
    print(style("Include directories:", Color.BOLD, Color.BLUE))
    for inc in incdirs:
        print("  ", inc)
    print(style("Sources:", Color.BOLD, Color.BLUE))
    for src in sources:
        print("  ", src)
    ok(f"listed {len(sources)} sources")
    return 0


def cmd_clean(args: argparse.Namespace) -> int:
    banner("CLEAN")
    build_dir = Path(args.build_dir).resolve()
    if build_dir.exists():
        shutil.rmtree(build_dir)
        ok(f"removed {build_dir}")
    else:
        warn(f"nothing to clean at {build_dir}")
    return 0


def _incdir_to_yosys_arg(inc: str) -> str:
    # "+incdir+/path" -> "-I/path"
    return "-I" + inc[len("+incdir+") :]


def cmd_fpga(args: argparse.Namespace) -> int:
    banner("FPGA BUILD")
    filelist = Path(args.filelist).resolve()
    lpf = Path(args.lpf).resolve()
    build_dir = Path(args.build_dir).resolve()
    bit_path = Path(args.bit).resolve()
    if not lpf.exists():
        raise FileNotFoundError(f"LPF not found: {lpf}")

    build_dir.mkdir(parents=True, exist_ok=True)
    bit_path.parent.mkdir(parents=True, exist_ok=True)

    incdirs, sources = parse_filelist(filelist)
    resolved = build_dir / "resolved_fpga.f"
    write_resolved_filelist(resolved, incdirs, sources)

    json_path = build_dir / f"{args.top}.json"
    cfg_path = build_dir / f"{args.top}.config"
    ys_path = build_dir / f"{args.top}.ys"

    yosys_inc = " ".join(shlex.quote(_incdir_to_yosys_arg(x)) for x in incdirs)
    yosys_src = " ".join(shlex.quote(str(src)) for src in sources)
    ys_body = (
        f"read_verilog -sv {yosys_inc} {yosys_src}\n"
        f"synth_ecp5 -top {shlex.quote(args.top)} -json {shlex.quote(str(json_path))}\n"
    )
    ys_path.write_text(ys_body)

    info(f"filelist: {filelist}")
    info(f"LPF: {lpf}")
    info(f"top: {args.top}")
    info(f"device: ECP5 {args.size} package {args.package} speed {args.speed}")
    info(f"resolved sources: {len(sources)}")

    run_cmd([args.yosys, "-s", str(ys_path)], "yosys synth_ecp5")

    nextpnr_cmd = [
        args.nextpnr,
        f"--{args.size}",
        "--package",
        args.package,
        "--speed",
        args.speed,
        "--freq",
        str(args.freq),
        "--json",
        str(json_path),
        "--lpf",
        str(lpf),
        "--textcfg",
        str(cfg_path),
    ]
    run_cmd(nextpnr_cmd, "nextpnr place-and-route")

    run_cmd([args.ecppack, "--compress", str(cfg_path), str(bit_path)], "ecppack bitstream")
    ok(f"bitstream ready: {bit_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="NeoCoreFX simulation/FPGA helper")
    sub = p.add_subparsers(dest="cmd", required=True)

    pb = sub.add_parser("build", help="compile simulation binary")
    pb.add_argument("--filelist", required=True)
    pb.add_argument("--out", required=True)
    pb.add_argument("--top", required=True)
    pb.add_argument("--iverilog", default="iverilog")
    pb.add_argument("--flags", default="-g2012 -Wall")
    pb.add_argument("--build-dir", required=True)
    pb.set_defaults(func=cmd_build)

    pr = sub.add_parser("run", help="run simulation binary")
    pr.add_argument("--sim", required=True)
    pr.add_argument("--vvp", default="vvp")
    pr.add_argument("--vvp-args", default="")
    pr.add_argument("--plusarg", default="")
    pr.set_defaults(func=cmd_run)

    pl = sub.add_parser("list", help="print resolved source order")
    pl.add_argument("--filelist", required=True)
    pl.set_defaults(func=cmd_list)

    pc = sub.add_parser("clean", help="remove build directory")
    pc.add_argument("--build-dir", required=True)
    pc.set_defaults(func=cmd_clean)

    pf = sub.add_parser("fpga", help="run FPGA build flow")
    pf.add_argument("--filelist", required=True)
    pf.add_argument("--top", required=True)
    pf.add_argument("--lpf", required=True)
    pf.add_argument("--build-dir", required=True)
    pf.add_argument("--size", default="85k")
    pf.add_argument("--package", default="CABGA381")
    pf.add_argument("--speed", default="8")
    pf.add_argument("--freq", default="25")
    pf.add_argument("--yosys", default="yosys")
    pf.add_argument("--nextpnr", default="nextpnr-ecp5")
    pf.add_argument("--ecppack", default="ecppack")
    pf.add_argument("--bit", required=True)
    pf.set_defaults(func=cmd_fpga)
    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.func(args))
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        print(style(f"[FAIL] {exc}", Color.BOLD, Color.RED), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
