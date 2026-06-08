# NeoCoreFX Simulation Workflow

> [!TIP]
> Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

Status: v0.5 practical runbook for integrated-core simulation.

## Quick Start (Authoritative Order)

```bash
make run_smoke
make run_forward_hazard
make run_frontend_timing
make run_any PROGRAM=mem/test_smoke.hex
```

This order validates:

1. baseline integrated-core operation (`run_smoke`)
2. forwarding-hazard regression lock (`run_forward_hazard`)
3. frontend stall+redirect timing guardrail (`run_frontend_timing`)
4. generic loader path and stats printing (`run_any`)

## Core Make Targets

- `make run_smoke`
  - deterministic smoke sequence in `tb_core_smoke`
- `make run_forward_hazard`
  - dedicated stale-WB-forward regression in `tb_forwarding_hazard`
- `make run_frontend_timing`
  - frontend combined stall+redirect timing regression in `tb_frontend_timing`
- `make run_any PROGRAM=mem/<program>.hex`
  - program execution through `tb_core_any`
- `make profile_any PROGRAM=...`
  - adds profiling output and optional memory dumps
- `make debug_any PROGRAM=...`
  - adds cycle-by-cycle debug stream
- `make waves_any PROGRAM=...`
  - emits `tb_core_any.vcd`

## Program Image Flow

Programs for `tb_core_any` use byte-per-line hex (`00`..`FF`) loaded from address `0x0000`.

Supported conversion paths:

```bash
make bin2hex BIN_INPUT=program.bin HEX_OUTPUT=mem/program.hex
make wordhex2byte WORDHEX_INPUT=program.wordhex HEX_OUTPUT=mem/program.hex
```

Python wrapper alternative:

```bash
python3 scripts/run_any.py --program mem/program.hex --max-cycles 200000
```

## Built-In Program Images

- `mem/test_smoke.hex`: ALU chain baseline + halt.
- `mem/test_halt.hex`: immediate halt path.
- `mem/test_forwarding_hazard.hex`: stale-WB-forward regression program.

## Profiling and Logs

`tb_core_any` prints:

- total cycles
- retired instructions
- retired IPC
- redirect count
- load-use stall cycles
- memory-wait stall cycles
- writeback fault flag
- full register dump

To extract profiling into JSON:

```bash
python3 scripts/profile_extract.py build/logs/core_any.log --out build/logs/core_any.json
```

## Practical Guidance

Recommended usage:

- keep CI on short deterministic images
- cap exploratory runs with `MAX_CYCLES`
- use `run_forward_hazard` as mandatory guardrail after hazard/forwarding edits
- use `run_frontend_timing` as mandatory guardrail after frontend control edits
- treat `tb_core_any` as integration/profiling harness, not a full ISA conformance suite
