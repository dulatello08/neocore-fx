# Program Hex Assets

Byte-per-line memory images for `tb_core_any.sv` (`+PROGRAM=<path>`).

## Format

- One byte per line in hex (`00`..`FF`).
- Bytes are loaded sequentially from address `0x0000`.
- Big-endian instruction words (MSB first).

## Included Programs

- `test_smoke.hex`: ALU chain + halt (`B .`).
- `test_halt.hex`: immediate halt at reset PC.

## Usage

```bash
make run_any PROGRAM=mem/test_smoke.hex
make profile_any PROGRAM=mem/test_smoke.hex
make debug_any PROGRAM=mem/test_smoke.hex
```
