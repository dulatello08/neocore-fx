# Testbench Directory Guide

> [!TIP]
> Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

## Purpose

`tb/` contains unit and integration testbenches for NeoCoreFX RTL.

## Integrated Core Testbenches

- `tb_core_smoke.sv`: deterministic integrated-core smoke run.
- `tb_forwarding_hazard.sv`: regression for stale WB-forward hazard behavior.
- `tb_core_any.sv`: generic program loader (`+PROGRAM=<byte-hex>`).

## Block-Level Testbenches

- `tb_biu.sv`
- `tb_mem.sv`
- `tb_halt_path.sv`

## Typical Commands

```bash
make run_smoke
make run_forward_hazard
make run_any PROGRAM=mem/test_smoke.hex
make run_any PROGRAM=mem/test_forwarding_hazard.hex
make profile_any PROGRAM=mem/test_smoke.hex
make debug_any PROGRAM=mem/test_smoke.hex
```

## Artifacts

Simulation outputs (`.vvp`, `.vcd`, resolved filelists) are generated under `build/`.

## Related Docs

- [../TESTING_AND_VERIFICATION.md](../TESTING_AND_VERIFICATION.md)
- [../docs/simulation-workflow.md](../docs/simulation-workflow.md)
