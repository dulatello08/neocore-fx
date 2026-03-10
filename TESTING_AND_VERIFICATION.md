# NeoCoreFX Testing and Verification Guide

> [!TIP]
> Docs Home: [DOCS_INDEX.md](DOCS_INDEX.md)

## Scope

This guide documents repository-backed simulation and regression workflows for the integrated NeoCoreFX core.

All commands assume repository root.

## Prerequisites

Required:

- `iverilog`
- `vvp`
- `python3`

Optional:

- waveform viewer for `.vcd` traces

Quick tool sanity check:

```bash
make check-sim
```

## Standard Verification Flow

```bash
make run_smoke
make run_forward_hazard
make run_frontend_timing
make run_any PROGRAM=mem/test_smoke.hex
```

## Test Target Matrix

### Deterministic Regression Benches

- `make run_smoke`
  - Bench: `tb/tb_core_smoke.sv`
  - Purpose: integrated ALU chain bring-up, halt path, baseline counters.

- `make run_forward_hazard`
  - Bench: `tb/tb_forwarding_hazard.sv`
  - Purpose: lock regression for stale WB-forward selection hazard.

- `make run_frontend_timing`
  - Bench: `tb/tb_frontend_timing.sv`
  - Purpose: lock regression for combined frontend stall+redirect timing behavior.

### Program Loader Bench

- `make run_any PROGRAM=mem/<program>.hex`
  - Bench: `tb/tb_core_any.sv`
  - Purpose: run arbitrary byte-hex program images through the integrated core.

- `make profile_any PROGRAM=mem/<program>.hex`
  - Adds profiler output (cycles, retire count, IPC, redirects, stall counters).

- `make debug_any PROGRAM=mem/<program>.hex`
  - Adds per-cycle runtime tracing.

- `make waves_any PROGRAM=mem/<program>.hex`
  - Dumps `tb_core_any.vcd` for waveform analysis.

## Program Images and Encoding

Program files for `run_any` are byte-per-line hex files loaded from address `0x0000`.

Included images:

- `mem/test_smoke.hex`
- `mem/test_halt.hex`
- `mem/test_forwarding_hazard.hex`

Conversion helpers:

```bash
make bin2hex BIN_INPUT=program.bin HEX_OUTPUT=mem/program.hex
make wordhex2byte WORDHEX_INPUT=program.wordhex HEX_OUTPUT=mem/program.hex
```

## Profiling Output Extraction

`profile_any` output can be post-processed into JSON:

```bash
python3 scripts/profile_extract.py build/logs/core_any.log --out build/logs/core_any.json
```

## Recommended Pre-Merge Minimum

Run all four before merging behavior changes:

1. `make run_smoke`
2. `make run_forward_hazard`
3. `make run_frontend_timing`
4. `make run_any PROGRAM=mem/test_smoke.hex`

For hazard-control or forwarding changes, also run:

1. `make run_any PROGRAM=mem/test_forwarding_hazard.hex`

## Failure Triage Order

When a test fails, debug in this order:

1. Decode and hazard select logic in `rtl/id_stage.sv`
2. Frontend control and prediction path in `rtl/if1_stage.sv` and `rtl/if2_stage.sv`
3. Forward mux and branch resolve behavior in `rtl/exe_stage.sv`
4. Stage-control wiring in `rtl/neocorefx_core.sv`
5. Memory handshake/response behavior in `rtl/mem_stage.sv` and `rtl/biu.sv`
6. Program encoding and byte order in `mem/*.hex`

## Related Docs

- [docs/simulation-workflow.md](docs/simulation-workflow.md)
- [tb/README.md](tb/README.md)
- [mem/README.md](mem/README.md)
- [MODULE_REFERENCE/README.md](MODULE_REFERENCE/README.md)
