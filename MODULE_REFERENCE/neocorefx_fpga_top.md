# neocorefx_fpga_top.sv - FPGA Board Wrapper

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`neocorefx_fpga_top` binds `neocorefx_top` to board IO for the ULX3S-style top-level interface.

## Module: `neocorefx_fpga_top`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk_25mhz` | input | 1 | Board clock |
| `btn` | input | 7 | Button input vector (`btn[0]` reset source) |
| `led` | output | 8 | LED output vector |

## Internal Behavior

- Instantiates `neocorefx_top`.
- Drives `en=1'b1`.
- Mirrors `count` to `led`.
