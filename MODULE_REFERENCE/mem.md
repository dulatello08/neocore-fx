# mem.sv - SoC Memory/MMIO Fabric

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`mem` is the SoC memory fabric. It connects the BIU I/D buses to BRAM, UART
MMIO, and the optional hardware debug plane.

## Module: `mem`

### Interfaces

- I-Bus port: read-only instruction fetch into `mem_bram`.
- D-Bus port: core load/store access to BRAM and MMIO.
- Core debug status/control ports.
- Board UART RX/TX pins.

### Main Behaviors

- Decodes BRAM at `0x0000_0000`.
- Decodes firmware UART MMIO at `0x4000_0000`.
- Decodes debug MMIO at `0x4000_0300` only when `INCLUDE_DEBUG=1`.
- Arbitrates halted-only debug memory masters behind core traffic.
- Routes the firmware UART either through `ncdb` virtual streaming
  (`INCLUDE_DEBUG=1`) or directly to the physical UART (`INCLUDE_DEBUG=0`).

### Debug Configuration

- `INCLUDE_DEBUG=1`: instantiates `debug_mmio`, `debug_uart_agent`, virtual
  firmware UART, and physical UART owned by `ncdb`.
- `INCLUDE_DEBUG=0`: does not instantiate debug blocks, leaves `0x4000_0300`
  unmapped, ties core debug control outputs inactive, and uses `u_uart_console`
  as the physical UART.

## Notes

The public module file is intentionally short. Implementation chunks live under
`rtl/memory/` so the source tree exposes the fabric area without creating a
single oversized file.
