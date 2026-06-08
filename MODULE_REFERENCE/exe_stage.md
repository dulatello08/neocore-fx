# exe_stage.sv - EXE Stage

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`exe_stage` applies operand forwarding, runs ALU/multiply operations, resolves branches/jumps, and emits EXE->MEM pipeline outputs.

## Module: `exe_stage`

### Key Interfaces

- Inputs: `id_*` decoded/control bundle from ID stage.
- Forward sources: `mem_fwd_data_i`, `wb_fwd_data_i`.
- Outputs: redirect signals and `mem_*` pipeline bundle.
- Halt path: `id_is_halt_i` propagates to `mem_is_halt_o`.

### Main Behaviors

- Forwarding muxes choose source operands from ID, MEM, or WB.
- ALU supports arithmetic, logic, compare, shifts, and multiply variants.
- Branch/jump path computes `redirect_valid_o` / `redirect_pc_o` and `mispredict_o`.
- Halt-tagged instructions do not require a special redirect path and are forwarded to MEM/WB for retirement signaling.

## Notes

`mem_result_o` carries either ALU/control result or effective address for load/store operations.
