# NeoCoreFX Hardware Debug Interface (v2)

Status: ncdb-first transport with permanent front-end UART ownership.

## Goals

- Keep hardware debug transport always available on the same physical UART.
- Keep firmware console usable at the same time.
- Remove claim/release races and irreversible ownership handoff.

## Architecture

- `ncdb` logic (`rtl/debug_uart_agent.sv`) always owns the physical UART pins.
- Firmware accesses a virtual UART MMIO console endpoint (same MMIO map at `0x4000_0000`).
- `ncdb` bridges traffic between host and firmware console:
  - Host RX: valid debug frames are consumed by `ncdb`; all other bytes are forwarded to firmware RX.
  - Firmware TX: bytes are forwarded out through `ncdb` to host TX.

This creates two logical planes over one wire:

- Debug control plane: framed binary protocol.
- Firmware console plane: normal UART byte stream.

## Core Halt/Step Semantics

- Debug halt/step requests are deferred until in-flight D-bus transactions complete.
- Halt boundary is a precise retire boundary (writeback-retire event).
- `B .` (`halt` alias) is unified with debug halt state and exports halt reason.

## Default UART Settings

- Physical UART default baud is 1,000,000 bps (`BAUDDIV=39` at 40 MHz fabric clock).
- `ncdb` host tool default baud is also 1,000,000 bps.

## MMIO Register Map (`0x4000_0300`)

- `0x00` `DBG_ID` (`"NCDB"`)
- `0x04` `DBG_CAPS`
- `0x08` `DBG_CTRL` (`halt`, `resume`, `step` request bits)
- `0x0C` `DBG_STATUS` (`halted`, `halt_reason`, `last_fault`)
- `0x10` `DBG_PC` (R: current PC, W: set PC while halted)
- `0x14` `DBG_CAUSE`
- `0x18` `DBG_GPR_IDX`
- `0x1C` `DBG_GPR_RDATA`
- `0x20` `DBG_GPR_WDATA`
- `0x24` `DBG_GPR_CMD`
- `0x28` `DBG_MEM_ADDR`
- `0x2C` `DBG_MEM_WDATA`
- `0x30` `DBG_MEM_RDATA`
- `0x34` `DBG_MEM_CMD`
- `0x38` `DBG_MEM_STATUS`
- `0x40` `DBG_CYCLE_COUNT`
- `0x44` `DBG_RETIRE_COUNT`
- `0x48` `DBG_REDIRECT_COUNT`
- `0x4C` `DBG_LOAD_STALL_COUNT`
- `0x50` `DBG_MEM_STALL_COUNT`

Mutating operations (`GPR write`, `MEM write`) are halted-only.

## UART Frame Protocol

Request frame:

- `SOF` `0xA5`
- `SEQ` (1 byte)
- `CMD` (1 byte)
- `LEN` (payload bytes)
- `PAYLOAD` (`LEN` bytes)
- `CRC16` (CCITT, big-endian, over `SOF..PAYLOAD`)

Response frame:

- `SOF` `0x5A`
- `SEQ`
- `STATUS`
- `LEN`
- `PAYLOAD`
- `CRC16`

Implemented command IDs:

- `0x00` `HELLO`
- `0x10` `HALT`
- `0x11` `RESUME`
- `0x12` `STEP`
- `0x13` `SET_PC` (payload: 32-bit big-endian PC, halted-only, internally aligned to 4 bytes)
- `0x20` `READ_STATUS`
- `0x21` `READ_GPR`
- `0x22` `WRITE_GPR`
- `0x23` `READ_MEM`
- `0x24` `WRITE_MEM`
- `0x25` `READ_COUNTERS`
- `0x26` `READ_MEM_BURST` (payload: `addr[31:0], size_code, count`; response: `count` words)
- `0x27` `SET_MEM_BURST` (payload: `addr[31:0], size_code, count, value[31:0]`)

Parser rule:

- Valid `A5...CRC` frames are consumed by `ncdb`.
- Any non-frame or invalid frame bytes are forwarded to firmware RX.

## Practical Caveat

- If a plain terminal program (for example `picocom`) is attached while `ncdb` issues binary debug responses, terminal output may show binary garbage for those bytes.
- In `ncdb tui`, host-side stream filtering consumes valid debug response frames (`0x5A...CRC`) and keeps those bytes out of the human console pane.

## Software Helpers

- C header: [`docs/debug_mmio.h`](debug_mmio.h)
- Host utility: `scripts/ncdb.py`

Examples:

```bash
python3 scripts/ncdb.py --port /dev/ttyUSB0 --baud 1000000 status
python3 scripts/ncdb.py --port /dev/ttyUSB0 halt
python3 scripts/ncdb.py --port /dev/ttyUSB0 pc-set 0x00000100
python3 scripts/ncdb.py --port /dev/ttyUSB0 resume
python3 scripts/ncdb.py --port /dev/ttyUSB0 gpr-read 3
python3 scripts/ncdb.py --port /dev/ttyUSB0 mem-read 0x00000100 4
python3 scripts/ncdb.py --port /dev/ttyUSB0 mem-read-burst 0x00000100 4 8
python3 scripts/ncdb.py --port /dev/ttyUSB0 mem-set-burst 0x00000200 4 0xDEADBEEF 16
python3 scripts/ncdb.py --port /dev/ttyUSB0 tui
```

Burst command notes:

- `mem-read-burst <addr> <size> <count>` uses native hardware burst command `0x26` (reduced framing overhead).
- `mem-set-burst <addr> <size> <value> <count>` uses native hardware burst command `0x27` (reduced framing overhead).
- Hardware read-burst response payload is capped at 32 bytes, so each frame returns up to 8 words; `ncdb` auto-chunks larger requests.

## `ncdb tui` (Integrated Console + Debug)

`ncdb tui` owns the serial port and provides:

- a live firmware console pane
- periodic debug status polling
- command mode for halt/resume/step/status/debug actions

Input modes:

- `console` mode: typed line is sent to firmware UART on Enter
- `cmd` mode: typed line is interpreted as a debugger command on Enter
- `Ctrl-A`: toggle `console`/`cmd` mode
- `Esc`: return to `console` mode

Useful command-mode commands:

- `help`
- `halt`, `resume`, `step`, `status`
- `pc set <addr>`
- `setpc <addr>` (alias)
- `bp` (toggle software breakpoint at current PC)
- `bp add <addr>`
- `bp del <addr>`
- `bp list`
- `bp clear`
- `quit`

## Software Breakpoints

`ncdb tui` software breakpoints are host-managed instruction patches:

- breakpoint word: canonical `B .` encoding (`0x40000000`)
- set flow: halt core -> read original instruction word -> write halt word
- clear flow: halt core -> restore original instruction word

Notes:

- breakpoints are word-addressed and require 4-byte alignment
- breakpoint map is session-local inside `ncdb tui`
- on `quit`, `ncdb` attempts best-effort restoration of all tracked breakpoints

## Hardware Programming Note

`ncdb` requires the current FPGA image to include `debug_uart_agent`. If `hello` times out, ensure the updated bitstream is loaded before debugging.
