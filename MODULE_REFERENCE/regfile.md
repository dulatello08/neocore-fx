# regfile.sv - Register File

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`regfile` is a 16x32 2-read/1-write register file with combinational reads and write-through bypass for same-cycle RAW cases.

## Module: `regfile`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `rst` | input | 1 | Synchronous reset |
| `rs1_addr_i` | input | 4 | Read address port 1 |
| `rs2_addr_i` | input | 4 | Read address port 2 |
| `rs1_data_o` | output | 32 | Read data port 1 |
| `rs2_data_o` | output | 32 | Read data port 2 |
| `we_i` | input | 1 | Write enable |
| `waddr_i` | input | 4 | Write address |
| `wdata_i` | input | 32 | Write data |

## Notes

- Register `r0` is hardwired as zero by blocking writes to address `0`.
- If `we_i` writes the same register being read, output returns `wdata_i`.

## Related Modules

- [id_stage.md](id_stage.md)
- [wb_stage.md](wb_stage.md)
