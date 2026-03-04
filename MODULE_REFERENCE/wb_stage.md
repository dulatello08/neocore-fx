# wb_stage.sv - WB Stage

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`wb_stage` gates register-file writes based on validity/fault state and exposes writeback status signals.

## Module: `wb_stage`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `memwb_valid_i` | input | 1 | MEM/WB entry valid |
| `memwb_rd_i` | input | 4 | Destination register |
| `memwb_reg_write_i` | input | 1 | Write intent |
| `memwb_data_i` | input | 32 | Write data |
| `memwb_mem_fault_i` | input | 1 | Memory fault flag |
| `memwb_fetch_fault_i` | input | 1 | Fetch fault flag |
| `memwb_illegal_i` | input | 1 | Illegal instruction flag |
| `rf_we_o` | output | 1 | Register file write enable |
| `rf_waddr_o` | output | 4 | Register file write address |
| `rf_wdata_o` | output | 32 | Register file write data |
| `wb_valid_o` | output | 1 | WB valid status |
| `wb_fault_o` | output | 1 | WB fault status |

## Notes

Writes are suppressed when any fault/illegal flag is set or destination register is zero.
