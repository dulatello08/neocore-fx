# id_stage.sv - ID Stage

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`id_stage` decodes instructions, generates control signals, detects load-use hazards, chooses forwarding selectors, and registers ID->EXE outputs.

## Module: `id_stage`

### Key Interfaces

- IF2 input bundle: instruction, PC, prediction/fault metadata.
- Register file read address/data interface.
- Hazard context from EXE/MEM/WB for forwarding and load-use checks.
- ID->EXE pipeline register outputs.

### Main Outputs

- `load_use_stall_o`: asserted when a load-use hazard requires stalling.
- `idex_*`: decoded operands and control for EXE stage.
- `idex_is_halt_o`: asserted when decode sees `B .` (`off16 == 0` unconditional branch).

## Notes

- Illegal decode suppresses write/memory/branch side effects.
- Forwarding selection prioritizes newest valid producer.
- `B .` is tagged as halt while remaining architecturally an unconditional branch encoding.
