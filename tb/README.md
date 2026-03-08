# Testbench Directory Guide

> [!TIP]
> Docs Home: [../README.md](../README.md)

## Purpose

`tb/` contains unit and integration testbenches for NeoCoreFX RTL.

## Integrated Core Testbenches

- `tb_core_smoke.sv`: deterministic integrated-core smoke run.
- `tb_core_any.sv`: generic program loader (`+PROGRAM=<byte-hex>`).

## Block-Level Testbenches

- `tb_biu.sv`
- `tb_mem.sv`
- `tb_halt_path.sv`

## Typical Commands

```bash
make run_smoke
make run_any PROGRAM=mem/test_smoke.hex
make profile_any PROGRAM=mem/test_smoke.hex
make debug_any PROGRAM=mem/test_smoke.hex
```

## Artifacts

Simulation outputs (`.vvp`, `.vcd`, resolved filelists) are generated under `build/`.
