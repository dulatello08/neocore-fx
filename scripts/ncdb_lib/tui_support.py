"""Small helpers for the ncdb curses TUI."""

from __future__ import annotations

import time

from .protocol import halt_reason_name


def add_log(log_lines: list[str], msg: str) -> None:
    ts = time.strftime("%H:%M:%S")
    log_lines.append(f"[{ts}] {msg}")
    if len(log_lines) > 300:
        del log_lines[: len(log_lines) - 300]


def append_console_bytes(console_lines: list[str], data: bytes) -> None:
    if not data:
        return
    for b in data:
        if b == 0x0A:
            console_lines.append("")
        elif b == 0x0D:
            continue
        elif b == 0x08:
            if console_lines and console_lines[-1]:
                console_lines[-1] = console_lines[-1][:-1]
        elif 0x20 <= b <= 0x7E or b == 0x09:
            console_lines[-1] += chr(b)
        else:
            console_lines[-1] += "."

    if len(console_lines) > 1200:
        del console_lines[: len(console_lines) - 1200]
    if len(console_lines[-1]) > 400:
        console_lines.append("")


def parse_u32(token: str) -> int:
    return int(token, 0) & 0xFFFFFFFF


def cmd_help() -> list[str]:
    return [
        "help",
        "quit",
        "halt | resume | step | status",
        "pc set <addr>",
        "bp                (toggle at current PC)",
        "bp add <addr>",
        "bp del <addr>",
        "bp list",
        "bp clear",
        "send <text>       (send one console line)",
    ]


def draw_line(stdscr, y: int, x: int, text: str, width: int) -> None:
    if y < 0:
        return
    try:
        stdscr.addnstr(y, x, text, max(0, width))
    except Exception:
        return


def render_screen(
    stdscr,
    last_status: dict[str, int],
    breakpoints: dict[int, int],
    console_lines: list[str],
    log_lines: list[str],
    input_mode: str,
    input_buf: str,
    last_err: str,
) -> None:
    h, w = stdscr.getmaxyx()
    stdscr.erase()

    halted = last_status.get("halted", 0)
    reason = halt_reason_name(last_status.get("halt_reason", 0))
    pc = last_status.get("pc", 0)

    bp_keys = sorted(breakpoints.keys())
    bp_preview = " ".join(f"0x{a:08x}" for a in bp_keys[:4])
    if len(bp_keys) > 4:
        bp_preview += " ..."

    draw_line(stdscr, 0, 0, "ncdb tui | integrated console + debug", w - 1)
    draw_line(stdscr, 1, 0, f"halted={halted} reason={reason} pc=0x{pc:08x} fault={last_status.get('last_fault', 0)}", w - 1)
    draw_line(
        stdscr,
        2,
        0,
        f"fault_pc=0x{last_status.get('fault_pc', 0):08x} fault_addr=0x{last_status.get('fault_addr', 0):08x}",
        w - 1,
    )
    draw_line(stdscr, 3, 0, f"breakpoints({len(bp_keys)}): {bp_preview}", w - 1)
    draw_line(stdscr, 4, 0, "console mode: Enter sends line | cmd mode: Enter runs command", w - 1)

    input_rows = 2
    log_rows = 4
    console_y0 = 6
    console_y1 = max(console_y0, h - input_rows - log_rows - 1)
    console_rows = max(1, console_y1 - console_y0 + 1)

    draw_line(stdscr, 5, 0, "-" * max(0, w - 1), w - 1)
    for i, ln in enumerate(console_lines[-console_rows:]):
        draw_line(stdscr, console_y0 + i, 0, ln, w - 1)

    log_y0 = console_y1 + 1
    draw_line(stdscr, log_y0, 0, "-" * max(0, w - 1), w - 1)
    for i, ln in enumerate(log_lines[-(log_rows - 1) :]):
        draw_line(stdscr, log_y0 + 1 + i, 0, ln, w - 1)

    input_prompt = "cmd> " if input_mode == "cmd" else "tx> "
    draw_line(stdscr, h - 2, 0, input_prompt + input_buf, w - 1)
    draw_line(
        stdscr,
        h - 1,
        0,
        "Ctrl-A mode toggle | cmd: quit/help/halt/resume/step/status/bp ... | err: " + last_err,
        w - 1,
    )
