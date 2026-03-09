# NeoCoreFX Simulation Workflow

Status: v0.5 practical runbook for integrated-core simulation.

## 1) Fast Path

```bash
make run_smoke
make run_any PROGRAM=mem/test_smoke.hex
make profile_any PROGRAM=mem/test_smoke.hex
```

## 2) Generic Program Flow

Programs for `tb_core_any` use **byte-per-line hex** (`00`..`FF`) loaded from address `0x0000`.

- Convert raw binaries:
  ```bash
  make bin2hex BIN_INPUT=program.bin HEX_OUTPUT=mem/program.hex
  ```
- Convert word-per-line hex (`32-bit`) to byte-per-line:
  ```bash
  make wordhex2byte WORDHEX_INPUT=program.wordhex HEX_OUTPUT=mem/program.hex
  ```
- Run with optional cycle cap:
  ```bash
  python3 scripts/run_any.py --program mem/program.hex --max-cycles 200000
  ```

## 3) Profiling Outputs

`tb_core_any` prints:

- total cycles
- retired instruction count
- retired IPC
- redirect count
- load-use stall cycles
- memory-wait stall cycles
- WB fault flag
- full register dump

To extract these into machine-readable JSON:

```bash
python3 scripts/profile_extract.py build/logs/core_any.log --out build/logs/core_any.json
```

## 4) Waveforms

```bash
make waves_any PROGRAM=mem/test_smoke.hex
```

Produces `tb_core_any.vcd` when `+WAVES` is enabled.

## 5) Current Caveat

The integrated frontend currently has edge cases around stall/redirect interactions.

Practical guidance for v0.5 runs:

- prefer short, deterministic smoke programs for CI bring-up
- use `MAX_CYCLES` in long exploratory runs
- treat `tb_core_any` as a bring-up/profiling harness, not yet a full architectural conformance oracle
