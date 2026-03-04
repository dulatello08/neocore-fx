# NeoCoreFX Pseudoinstruction Policy

Status: v0.5 companion document
Parent: [isa-v0.md](isa-v0.md)

## 1) What Is a Pseudoinstruction

A pseudoinstruction is a mnemonic accepted by the assembler that does **not** correspond to a single hardware opcode. The assembler expands it into one or more real instructions before encoding.

Pseudoinstructions exist to improve readability and reduce programmer error. They never introduce new architectural state or semantics — they are purely syntactic sugar over the base ISA.

## 2) Assembler Obligations

1. Every pseudoinstruction expansion must be **documented and deterministic**. The assembler must always produce the same instruction sequence for the same pseudoinstruction and operands.
2. Expansion must be **context-free** — it depends only on the pseudoinstruction's own operands, never on surrounding instructions.
3. The assembler **must not** silently clobber registers that the programmer did not name. If a pseudoinstruction requires a scratch register, it must be an explicit operand or use a dedicated assembler temporary (see §4).
4. If a pseudoinstruction cannot be expanded because the operand is out of range, the assembler **must** emit a diagnostic error. Silent truncation is forbidden.

## 3) Recognized Pseudoinstructions (v0.5)

### 3.1 `NOP`

- Expansion: encoding `0x00000000`.
- Notes: this is also a real encoding (class `0x0`, op `0x0`, all zeros). Listed here because it has no operands and behaves as a pseudo in the assembler surface.

### 3.2 `RET`

- Expansion: `JALR 0, 15, 0`.
- Notes: link address is discarded (targets `r0`). Uses ABI convention that `r15` holds the return address.

### 3.3 `MOV rd, rs`

- Expansion: `ADDI rd, rs, 0`.
- Notes: copies register `rs` to `rd`.

### 3.4 `LI rd, imm32`

- Load 32-bit immediate into `rd`.
- Expansion depends on value:
  - If `imm32` fits in 16 bits unsigned (`0x0000..0xFFFF`): `ORI rd, 0, imm32`.
  - If `imm32` fits in 16 bits signed (`-32768..32767`): `ADDI rd, 0, imm32`.
  - If `imm32[15:0] == 0`: `LUI rd, imm32[31:16]`.
  - Otherwise: `LUI rd, imm32[31:16]` then `ORI rd, rd, imm32[15:0]`.
- Notes: the assembler picks the shortest legal expansion. `ORI` is preferred for the low-half-only case because it zero-extends (no sign pollution).

### 3.5 `LA rd, label`

- Load the absolute address of `label` into `rd`.
- Expansion: same as `LI rd, <address of label>`, with a relocation record emitted for the linker.
- See [relocations.md](relocations.md) §3 for the relocation types used.

### 3.6 `BGT rs1, rs2, off16`

- Expansion: `BLT rs2, rs1, off16` (swap operands).
- Notes: removed as a hardware instruction but retained as a convenience pseudo.

### 3.7 `BGTU rs1, rs2, off16`

- Expansion: `BLTU rs2, rs1, off16` (swap operands).

### 3.8 `BGE rs1, rs2, off16`

- Expansion: `BLT rs2, rs1, off16`? No — `BGE` is NOT the same as swapping `BLT`. Correct expansion:
  - `BLT rs1, rs2, +8` (skip the branch)
  - `B off16_adjusted`
- **Decision needed**: whether to support `BGE`/`BGEU` as pseudos at all in v0, given the two-instruction cost. For now, **not recognized**. Programmers should use `BLT` with inverted logic or `SLT` + `BNE`.

### 3.9 `CALL label`

- Expansion: see [far-branching.md](far-branching.md) §2 for near/far strategy.
- Near case (label within ±2 MiB): `JAL 15, off20`.
- Far case: `LUI at, hi16` / `ORI at, at, lo16` / `JALR 15, at, 0` where `at` is the assembler temporary.

### 3.10 `J label`

- Unconditional jump (no link).
- Near case: `JAL 0, off20` (link discarded).
- Far case: `LUI at, hi16` / `ORI at, at, lo16` / `JALR 0, at, 0`.

### 3.11 `HALT`

- Expansion: `B 0` (assembly equivalent: `B .`).
- Notes:
  - Represents a canonical self-branch halt loop in software-visible encoding.
  - Current RTL exports a `halted` signal when this encoding retires in WB.

## 4) Assembler Temporary Register (`at`)

- Register `1` is reserved by ABI convention as the **assembler temporary** (`at`).
- The assembler may use `r1` as a scratch register when expanding multi-instruction pseudos (e.g., far calls, `LI` with 32-bit values).
- Programmer code **should not** rely on `r1` being preserved across pseudo-expansions.
- The assembler **must** emit a warning or error if the programmer explicitly uses `r1` as a source/destination in the same context as a pseudo that clobbers it.

## 5) Pseudo vs. Macro

- Pseudoinstructions are **built into the assembler** and have fixed, documented expansions.
- User-defined macros are a separate assembler feature (if supported) and are **not** part of the ISA specification.
- The assembler must clearly distinguish pseudo-expansions from user macros in listings and diagnostics.
