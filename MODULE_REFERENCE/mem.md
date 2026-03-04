# mem.sv - Memory Model

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`mem` is a dual-port 32-bit word array memory model used by testbenches.

## Module: `mem`

### Interfaces

- I-Bus port: read-only, word-aligned fetch.
- D-Bus port: read/write with byte-lane selects.

### Main Behaviors

- I-Bus and D-Bus responses are registered (1-cycle behavior).
- I-Bus flags misaligned or out-of-range access as error.
- D-Bus applies lane-merge writes through `mem_apply_write_sel` from [mem_pkg.md](mem_pkg.md).

## Notes

Memory initializes to zero on startup for deterministic simulation.
