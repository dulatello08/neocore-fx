# Module Reference Documentation

> [!TIP]
> Docs Home: [../README.md](../README.md)

This directory contains module-level references for the NeoCoreFX RTL.

## Core Pipeline

- [if1_stage.sv](if1_stage.md): IF1 PC selection and fetch request generation.
- [if2_stage.sv](if2_stage.md): IF2 fetch latch and static branch prediction.
- [id_stage.sv](id_stage.md): Decode, hazard detection, and ID/EX register.
- [exe_stage.sv](exe_stage.md): Execute, forwarding muxes, and branch redirect logic.
- [mem_stage.sv](mem_stage.md): Memory transactions, load extraction, and MEM/WB register.
- [wb_stage.sv](wb_stage.md): Writeback gating, fault kill logic, and `halted` assertion.

## Shared Blocks

- [core_pkg.sv](core_pkg.md): Shared enums and immediate helper functions.
- [regfile.sv](regfile.md): 16x32 register file with bypass-on-write reads.
- [biu.sv](biu.md): CPU I/D request to I-Bus/D-Bus bridge.
- [mem_pkg.sv](mem_pkg.md): Memory map constants and write-merge helpers.
- [mem.sv](mem.md): BRAM-like dual-port memory model.

## Top-Level Wrappers

- [counter.sv](counter.md): Simple synchronous up-counter.
- [neocorefx_top.sv](neocorefx_top.md): Minimal wrapper around `counter`.
- [neocorefx_fpga_top.sv](neocorefx_fpga_top.md): Board top-level wrapper.

## Hierarchy Snapshot

```text
neocorefx_fpga_top
└── neocorefx_top
    └── counter

pipeline integration blocks
├── if1_stage -> if2_stage -> id_stage -> exe_stage -> mem_stage -> wb_stage
├── regfile
├── biu
└── mem
```
