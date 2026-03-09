# Program Hex Assets

Byte-per-line memory images for `tb_core_any.sv` (`+PROGRAM=<path>`).

> [!TIP]
> Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

## Format

- One byte per line in hex (`00`..`FF`).
- Bytes are loaded sequentially from address `0x0000`.
- Big-endian instruction words (MSB first).

## Included Programs

- `test_smoke.hex`: ALU chain + halt (`B .`).
- `test_halt.hex`: immediate halt at reset PC.
- `test_forwarding_hazard.hex`: stale WB-forward regression program.

## Usage

```bash
make run_any PROGRAM=mem/test_smoke.hex
make run_any PROGRAM=mem/test_forwarding_hazard.hex
make profile_any PROGRAM=mem/test_smoke.hex
make debug_any PROGRAM=mem/test_smoke.hex
```
