# if1_stage.sv - IF1 Stage

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`if1_stage` selects the next fetch PC from redirect, prediction, or sequential flow and emits an instruction request.

## Module: `if1_stage`

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `RESET_PC` | `32'h0000_0000` | PC reset value |

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `rst` | input | 1 | Reset |
| `stall_i` | input | 1 | Stall IF1/IF2 update |
| `redirect_valid_i` | input | 1 | Redirect valid from EXE |
| `redirect_pc_i` | input | 32 | Redirect target PC |
| `pred_valid_i` | input | 1 | Prediction valid |
| `pred_taken_i` | input | 1 | Prediction taken flag |
| `pred_target_i` | input | 32 | Predicted target |
| `i_req_o` | output | 1 | Instruction request to BIU |
| `i_addr_o` | output | 32 | Instruction fetch address |
| `if2_valid_o` | output | 1 | IF1->IF2 valid |
| `if2_pc_o` | output | 32 | IF1->IF2 PC |
| `if2_pred_taken_o` | output | 1 | IF1->IF2 predicted-taken tag |
| `pc_o` | output | 32 | Current PC register |

## Notes

Redirect has highest priority, then prediction, then sequential flow.
