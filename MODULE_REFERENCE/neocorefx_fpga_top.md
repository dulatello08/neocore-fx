# neocorefx_fpga_top.sv - FPGA Board Wrapper

> [!TIP]
> Module Index: [README.md](README.md) | Docs Home: [../README.md](../README.md)

## Overview

`neocorefx_fpga_top` binds `neocorefx_top` to ULX3S-facing clock/button/LED IO.

## Module: `neocorefx_fpga_top`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk_25mhz` | input | 1 | Board clock |
| `btn` | input | 7 | Button vector (`btn[0]` reset source) |
| `led` | output | 8 | LED status outputs |

## LED Map

- `led[7]`: reset asserted
- `led[6]`: heartbeat toggle
- `led[5]`: PLL unlocked
- `led[4]`: WB fault
- `led[3]`: halted
- `led[2]`: PC activity bit
- `led[1]`: memory stall activity
- `led[0]`: load-use stall activity

## Notes

- `neocorefx_top` is run with `en=1'b1` in this wrapper.
- The LED map prioritizes bring-up observability over ABI semantics.

## Related Modules

- [neocorefx_top.md](neocorefx_top.md)
- `neocorefx_core.sv`
