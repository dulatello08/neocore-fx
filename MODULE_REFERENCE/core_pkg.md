# core_pkg.sv - Shared Definitions

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`core_pkg` defines shared enums and immediate helper functions used by pipeline stages.

## Key Types

- `alu_op_t`: ALU operation select (`ALU_ADD`, `ALU_SUB`, `ALU_AND`, ...)
- `branch_t`: branch selector (`BR_NONE`, `BR_UNCOND`, `BR_EQ`, ...)
- `mem_size_t`: memory width selector (`SIZE_BYTE`, `SIZE_HALF`, `SIZE_WORD`)
- `fwd_sel_t`: forwarding source selector (`FWD_NONE`, `FWD_MEM`, `FWD_WB`)

## Constants

- `GPR_COUNT`: number of general-purpose registers (16)

## Helper Functions

- `sext16`: sign-extend 16-bit immediate to 32-bit
- `zext16`: zero-extend 16-bit immediate to 32-bit
- `sext16_shift2`: sign-extend 16-bit immediate, then left shift by 2
- `sext20_shift2`: sign-extend 20-bit immediate, then left shift by 2

## Related Modules

- [id_stage.md](id_stage.md)
- [if2_stage.md](if2_stage.md)
- [exe_stage.md](exe_stage.md)
- [mem_stage.md](mem_stage.md)
