# if2_stage.sv - IF2 Stage

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`if2_stage` latches fetch responses, emits ID-stage inputs, and computes static branch prediction (unconditional branch and BTFNT-style conditional behavior).

## Module: `if2_stage`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `rst` | input | 1 | Reset |
| `stall_i` | input | 1 | Hold IF2/ID outputs |
| `flush_i` | input | 1 | Bubble IF2/ID outputs |
| `if1_valid_i` | input | 1 | IF1 valid |
| `if1_pc_i` | input | 32 | IF1 PC |
| `if1_pred_taken_i` | input | 1 | IF1 prediction tag |
| `i_done_i` | input | 1 | BIU fetch done |
| `i_rdata_i` | input | 32 | Instruction word |
| `i_err_i` | input | 1 | Fetch error |
| `id_valid_o` | output | 1 | IF2->ID valid |
| `id_pc_o` | output | 32 | IF2->ID PC |
| `id_inst_o` | output | 32 | IF2->ID instruction |
| `id_pred_taken_o` | output | 1 | IF2->ID prediction tag |
| `id_fetch_fault_o` | output | 1 | Fetch fault tag |
| `pred_valid_o` | output | 1 | Predictor feedback valid |
| `pred_taken_o` | output | 1 | Predictor feedback taken |
| `pred_target_o` | output | 32 | Predictor feedback target |

## Notes

Prediction helpers (`sext16_shift2`, `sext20_shift2`) come from [core_pkg.md](core_pkg.md).
