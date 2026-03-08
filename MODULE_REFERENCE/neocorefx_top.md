# neocorefx_top.sv - Core + BIU + BRAM Wrapper

> [!TIP]
> Module Index: [README.md](README.md) | Docs Home: [../README.md](../README.md)

## Overview

`neocorefx_top` is the integrated single-chip wrapper used for simulation and board-level integration.

It instantiates:

- `neocorefx_core`
- `biu`
- `mem`

## Module: `neocorefx_top`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| `en` | input | 1 | Run enable into core |
| `count` | output | 8 | Compact status signature |
| `halted_o` | output | 1 | Sticky halt status |
| `current_pc_o` | output | 32 | Current frontend PC |
| `cycle_count_o` | output | 32 | Active cycle count |
| `retire_count_o` | output | 32 | Retired instruction count |
| `branch_redirect_count_o` | output | 32 | Redirect count |
| `load_stall_count_o` | output | 32 | Load-use stall count |
| `mem_stall_count_o` | output | 32 | Memory-wait stall count |
| `wb_fault_o` | output | 1 | WB fault status |

## Key Behavior

### Integration wiring

- Core I-channel connects through `biu` to memory I-bus.
- Core D-channel connects through `biu` to memory D-bus.
- `mem` provides dual-port BRAM-like backing store for both channels.

### Status signature (`count[7:0]`)

- `count[7]`: halted
- `count[6]`: wb fault
- `count[5]`: mispredict pulse
- `count[4]`: memory-wait stall pulse
- `count[3]`: load-use stall pulse
- `count[2]`: wb valid pulse
- `count[1:0]`: low PC activity bits

## Related Modules

- `neocorefx_core.sv`
- [biu.md](biu.md)
- [mem.md](mem.md)
- [neocorefx_fpga_top.md](neocorefx_fpga_top.md)
