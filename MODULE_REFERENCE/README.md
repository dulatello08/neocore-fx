# Module Reference Documentation

> [!TIP]
> Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

This directory contains module-level references for the NeoCoreFX RTL.

## Core Integration

- `neocorefx_core.sv`: Main 6-stage integrated core.
- [neocorefx_top.sv](neocorefx_top.md): Core + BIU + BRAM wrapper.
- [neocorefx_fpga_top.sv](neocorefx_fpga_top.md): FPGA/board top-level wrapper.

## Pipeline Stages

- [if1_stage.sv](if1_stage.md)
- [if2_stage.sv](if2_stage.md)
- [id_stage.sv](id_stage.md)
- [exe_stage.sv](exe_stage.md)
- [mem_stage.sv](mem_stage.md)
- [wb_stage.sv](wb_stage.md)

## Shared Blocks

- [core_pkg.sv](core_pkg.md)
- [regfile.sv](regfile.md)
- [biu.sv](biu.md)
- [mem_pkg.sv](mem_pkg.md)
- [mem.sv](mem.md)

## Auxiliary Blocks

- [counter.sv](counter.md)

## Hierarchy Snapshot

```text
neocorefx_fpga_top
└── neocorefx_top
    ├── neocorefx_core
    │   ├── if1_stage
    │   ├── if2_stage
    │   ├── id_stage
    │   ├── exe_stage
    │   ├── mem_stage
    │   ├── wb_stage
    │   └── regfile
    ├── biu
    └── mem
```

## Related Docs

- [../TESTING_AND_VERIFICATION.md](../TESTING_AND_VERIFICATION.md)
- [../docs/simulation-workflow.md](../docs/simulation-workflow.md)
