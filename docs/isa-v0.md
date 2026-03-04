# NeoCoreFX ISA v0.5 Draft

Status: collaborative draft (v0.5 — zero-extend bitwise-I, removed BGT/BGTU/BRO/BRZ/OV/Z/ADDIU, added LPC, explicit r0 rules)
Target: Lattice ECP5, single-issue, deep-pipeline, frequency-focused fixed-width load/store CPU

### Companion Documents

| Document | Scope |
|---|---|
| [pseudoinstructions.md](pseudoinstructions.md) | Pseudoinstruction policy, expansion rules, assembler temporary |
| [relocations.md](relocations.md) | Relocation types, label materialization, constant rules |
| [far-branching.md](far-branching.md) | Far branch/call expansion strategy, linker veneers |
| [pc-relative.md](pc-relative.md) | Exact PC-relative semantics, offset computation, PIC patterns |
| [exceptions-future.md](exceptions-future.md) | Future exception model entry point (v0 has no exceptions) |
| [bus-architecture.md](bus-architecture.md) | NCX Bus protocol, address map, phased memory system evolution |
| [microarchitecture.md](microarchitecture.md) | 6-stage pipeline design, hazards, forwarding, branch prediction |

## 1) Locked Decisions (Current)

1. ISA family name: `NeoCoreFX`.
2. Fixed-width 32-bit instructions.
3. 16 general-purpose registers (`0..15`). Register `0` is hardwired to zero (see §2a for full semantics).
4. Assembly register syntax uses plain numeric tokens (`0..15`) with no prefix.
5. Assembly operand order: `OP rd, rs1, rs2`.
6. No standalone compare instruction.
7. Branch prediction baseline: static BTFNT.
8. Branch and jump displacements are word-relative (`target = pc + (sext(offset) << 2)`).
9. Canonical `NOP` encoding is `0x00000000`.
10. Deep pipeline direction; initial implementation likely starts around 5 stages and can expand.
11. Multiply family includes `MUL`, `MULH`, `MULHU`, `MULHSU`; target single-cycle execute via DSP path.
12. No fused MAC (`MADD/MSUB`) in v0.
13. No divide/remainder in v0.
14. Modified Harvard implementation model (separate I/D paths) with unified logical address space.
15. No cache-maintenance instructions in v0.
16. Misaligned data accesses are architecturally undefined in v0.
17. No privilege mode split in v0.
18. No CSR architectural surface in v0.
19. `15` as link register is ABI convention only, not ISA-reserved.
20. Branch mnemonic direction is NeoCoreFX-style (`B`, `BE`, `BNE`, `BLT`, `BLTU`).
21. No internal condition flags (no `OV`, no `Z`). All branches are register-compare or unconditional.
22. `ANDI`, `ORI`, and `XORI` zero-extend their 16-bit immediate operand.
23. `LPC` forms a PC-relative address: `rd = pc + (sext(off20) << 2)`.
24. Canonical 32-bit immediate assembly: `LUI rd, hi16` then `ORI rd, rd, lo16`.
25. `JALR` target is word-aligned in hardware: `pc = (rs1 + sext(off16)) & ~3`.
26. Interrupts are not part of v0.
27. Final encoding uses split opcode fields (class + op), not a single flat opcode.
28. `rd`, `rs1`, and `rs2` stay in fixed bit positions across compatible instruction forms.
29. `0x00000000` is permanently reserved as canonical `NOP`.
30. Register `1` is reserved by ABI as assembler temporary (`at`); may be clobbered by pseudoinstruction expansions (see [pseudoinstructions.md](pseudoinstructions.md)).
31. PC-relative semantics: `pc` in offset formulas is the address of the instruction itself (see [pc-relative.md](pc-relative.md)).

## 2) Architectural Model

- XLEN: 32-bit.
- Endianness: big-endian.
- Byte-addressed memory.
- Instruction alignment: 4-byte aligned fetch.
- ISA-level address space: unified logical map.
- Microarchitecture-level memory paths: modified Harvard (independent instruction/data channels).
- No internal condition/status flags. All conditional branches compare two register operands directly.

Platform trajectory:
- BRAM-backed bring-up initially.
- BRAM-backed I-side and D-side cache-like structures expected.
- Later SDRAM-backed memory system without ISA semantic changes.
- DMA expected later; no explicit cache ops in v0 ISA.

### 2a) Register `0` (Hardwired Zero) Semantics

- Register `0` always reads as `0x00000000`.
- Any instruction that names `0` as `rd` executes normally (all side effects such as memory access, address computation, and `pc` update proceed as specified), but the register write is silently discarded.
- Example: `SW 3, 0(1)` with `rs2=3` stores `r3` to memory — even if `rd` happens to be `0` in a different instruction, the store still occurs.
- Example: `JAL 0, offset` jumps and the link address is computed but not written.

## 3) Assembly Surface

Register tokens:
- No `r` prefix.
- Registers are written as plain indices (`0..15`).

Case style:
- Mnemonics are shown uppercase in this document for readability.
- ISA is case-agnostic; assembler case handling is a toolchain choice.

## 4) Instruction Catalog (Per-Instruction)

Encoding details are defined in Section 9 of this document.

Encoding principles already frozen:
1. Split opcode structure (class + op) for timing-friendly decode.
2. Fixed register field positions for `rd`, `rs1`, `rs2` where instruction form permits.
3. `0x00000000` always decodes as `NOP`.

### 4.1 Integer ALU (Register)

#### `ADD rd, rs1, rs2`
- ID: `ALU.0`
- Meaning: `rd = rs1 + rs2`.
- Modifiers/notes:
1. Wraparound two's-complement arithmetic.
2. No overflow trap.

#### `SUB rd, rs1, rs2`
- ID: `ALU.1`
- Meaning: `rd = rs1 - rs2`.
- Modifiers/notes:
1. Wraparound two's-complement arithmetic.
2. No overflow trap.

#### `AND rd, rs1, rs2`
- ID: `ALU.2`
- Meaning: `rd = rs1 & rs2`.

#### `OR rd, rs1, rs2`
- ID: `ALU.3`
- Meaning: `rd = rs1 | rs2`.

#### `XOR rd, rs1, rs2`
- ID: `ALU.4`
- Meaning: `rd = rs1 ^ rs2`.

#### `SLT rd, rs1, rs2`
- ID: `ALU.5`
- Meaning: `rd = (signed(rs1) < signed(rs2)) ? 1 : 0`.

#### `SLTU rd, rs1, rs2`
- ID: `ALU.6`
- Meaning: `rd = (unsigned(rs1) < unsigned(rs2)) ? 1 : 0`.

### 4.2 Integer ALU (Immediate)

#### `ADDI rd, rs1, imm16`
- ID: `ALUI.0`
- Meaning: `rd = rs1 + sext(imm16)`.

#### `ANDI rd, rs1, imm16`
- ID: `ALUI.1`
- Meaning: `rd = rs1 & zext(imm16)`.
- Modifiers/notes:
  1. Immediate is **zero-extended** to 32 bits.

#### `ORI rd, rs1, imm16`
- ID: `ALUI.2`
- Meaning: `rd = rs1 | zext(imm16)`.
- Modifiers/notes:
  1. Immediate is **zero-extended** to 32 bits.

#### `XORI rd, rs1, imm16`
- ID: `ALUI.3`
- Meaning: `rd = rs1 ^ zext(imm16)`.
- Modifiers/notes:
  1. Immediate is **zero-extended** to 32 bits.

#### `LUI rd, imm16`
- ID: `ALUI.4`
- Meaning: `rd = imm16 << 16`.
- Modifiers/notes:
  1. Low 16 bits are zero.
  2. Canonical 32-bit immediate assembly: `LUI rd, hi16` then `ORI rd, rd, lo16`.

### 4.3 Shift

#### `SLL rd, rs1, rs2`
- ID: `SHIFT.0`
- Meaning: `rd = rs1 << (rs2[4:0])`.

#### `SRL rd, rs1, rs2`
- ID: `SHIFT.1`
- Meaning: `rd = rs1 >> (rs2[4:0])` (logical).

#### `SRA rd, rs1, rs2`
- ID: `SHIFT.2`
- Meaning: `rd = signed(rs1) >>> (rs2[4:0])` (arithmetic).

#### `SLLI rd, rs1, shamt5`
- ID: `SHIFT.3`
- Meaning: `rd = rs1 << shamt5`.

#### `SRLI rd, rs1, shamt5`
- ID: `SHIFT.4`
- Meaning: `rd = rs1 >> shamt5` (logical).

#### `SRAI rd, rs1, shamt5`
- ID: `SHIFT.5`
- Meaning: `rd = signed(rs1) >>> shamt5`.

### 4.4 Multiply

#### `MUL rd, rs1, rs2`
- ID: `MUL.0`
- Meaning: `rd = (rs1 * rs2)[31:0]`.

#### `MULH rd, rs1, rs2`
- ID: `MUL.1`
- Meaning: `rd = (signed(rs1) * signed(rs2))[63:32]`.

#### `MULHU rd, rs1, rs2`
- ID: `MUL.2`
- Meaning: `rd = (unsigned(rs1) * unsigned(rs2))[63:32]`.

#### `MULHSU rd, rs1, rs2`
- ID: `MUL.3`
- Meaning: `rd = (signed(rs1) * unsigned(rs2))[63:32]`.

### 4.5 Load

#### `LB rd, imm16(rs1)`
- ID: `LD.0`
- Meaning: `rd = sext(mem8[rs1 + sext(imm16)])`.

#### `LBU rd, imm16(rs1)`
- ID: `LD.1`
- Meaning: `rd = zext(mem8[rs1 + sext(imm16)])`.

#### `LH rd, imm16(rs1)`
- ID: `LD.2`
- Meaning: `rd = sext(mem16[rs1 + sext(imm16)])`.

#### `LHU rd, imm16(rs1)`
- ID: `LD.3`
- Meaning: `rd = zext(mem16[rs1 + sext(imm16)])`.

#### `LW rd, imm16(rs1)`
- ID: `LD.4`
- Meaning: `rd = mem32[rs1 + sext(imm16)]`.

### 4.6 Store

#### `SB rs2, imm16(rs1)`
- ID: `ST.0`
- Meaning: `mem8[rs1 + sext(imm16)] = rs2[7:0]`.

#### `SH rs2, imm16(rs1)`
- ID: `ST.1`
- Meaning: `mem16[rs1 + sext(imm16)] = rs2[15:0]`.

#### `SW rs2, imm16(rs1)`
- ID: `ST.2`
- Meaning: `mem32[rs1 + sext(imm16)] = rs2[31:0]`.

### 4.7 Branch and Jump (NeoCoreFX Naming)

#### `B off16`
- ID: `BR.0`
- Meaning: `pc = pc + (sext(off16) << 2)`.
- Modifiers/notes:
1. Unconditional relative branch.
2. `B 0` (assembly form `B .`) is the canonical software halt loop encoding. Hardware may treat this as a retire-time halt event.

#### `BE rs1, rs2, off16`
- ID: `BR.1`
- Meaning: if `rs1 == rs2` then `pc = pc + (sext(off16) << 2)`.

#### `BNE rs1, rs2, off16`
- ID: `BR.2`
- Meaning: if `rs1 != rs2` then `pc = pc + (sext(off16) << 2)`.

#### `BLT rs1, rs2, off16`
- ID: `BR.3`
- Meaning: if `signed(rs1) < signed(rs2)` then `pc = pc + (sext(off16) << 2)`.

#### `BLTU rs1, rs2, off16`
- ID: `BR.4`
- Meaning: if `unsigned(rs1) < unsigned(rs2)` then `pc = pc + (sext(off16) << 2)`.

#### `JAL rd, off20`
- ID: `JMP.0`
- Meaning:
  1. `rd = pc + 4`.
  2. `pc = pc + (sext(off20) << 2)`.

#### `JALR rd, rs1, off16`
- ID: `JMP.1`
- Meaning:
  1. `tmp = rs1 + sext(off16)`.
  2. `rd = pc + 4`.
  3. `pc = tmp & ~3`.

#### `LPC rd, off20`
- ID: `JMP.2`
- Meaning: `rd = pc + (sext(off20) << 2)`.
- Modifiers/notes:
  1. PC-relative address forming. Does not branch or update `pc` beyond the normal `pc + 4` advance.
  2. Used for computing addresses of data or code labels relative to the current PC.
  3. If `rd` is `0`, the computed address is discarded (r0 semantics).

#### `RET`
- ID: `JMP.3` (assembler alias)
- Meaning: `JALR 0, 15, 0`.
- Modifiers/notes:
  1. The link address (`pc + 4`) targets `r0`, so it is discarded.

#### `NOP`
- ID: `JMP.4`
- Meaning: no architected state change except normal `pc = pc + 4`.
- Modifiers/notes:
  1. Fixed encoding is `0x00000000`.

### 4.8 System/Control Instructions

- None in v0 architectural surface.
- Debug/trap/control instructions are deferred to a later ISA revision.

## 5) Exceptions (v0, No Interrupts)

No exceptions, interrupts, privilege levels, or trap registers in v0. Illegal instruction and address-fault detection is implementation-defined.

See [exceptions-future.md](exceptions-future.md) for the planned v1+ exception architecture and the v0 design choices that support it.

## 6) ABI Sketch (Draft)

- `0`: hardwired zero.
- `1`: assembler temporary (`at`). Reserved for pseudoinstruction expansion; not preserved across pseudo-expansions. See [pseudoinstructions.md](pseudoinstructions.md) §4.
- `2..7`: caller-saved temporaries/arguments.
- `8..11`: callee-saved.
- `12`: global pointer (optional).
- `13`: stack pointer (`sp`).
- `14`: frame pointer (`fp`) optional.
- `15`: link register by ABI convention (`lr` alias optional).

## 8) Next Decisions

1. The first revision that introduces architected exception control/state — see [exceptions-future.md](exceptions-future.md).
2. Linker veneer strategy finalization — see [far-branching.md](far-branching.md) §4.2.
3. Object file format specification — see [relocations.md](relocations.md) §6.


## 9) Bit-Level Encoding (Merged)

The following section is merged from the former  and is now the canonical encoding definition for NeoCoreFX v0.
Status: frozen encoding for NeoCoreFX ISA v0.5 instruction set

## 1) Core Encoding Rules

1. Instruction width is fixed at 32 bits.
2. Top-level opcode is split into two fields:
- `CLASS = inst[31:28]`
- `OP = inst[27:24]`
3. Register fields stay fixed where present:
- `rd = inst[23:20]`
- `rs1 = inst[19:16]`
- `rs2 = inst[15:12]`
4. `0x00000000` is permanently reserved as `NOP`.

## 2) Class Map

- `0x0`: ALU-R / shift-R / multiply (R3 form) + `NOP`
- `0x1`: ALU-I / shift-I / `LUI` (I16 form)
- `0x2`: load (I16 form)
- `0x3`: store (S16-split form)
- `0x4`: branch (B16-split form)
- `0x5`: jump/call (J20/JR16 forms)
- `0x6..0xF`: reserved (illegal in v0)

## 3) Instruction Forms

### 3.1 R3 Form (3-register)

Used by class `0x0` arithmetic/logic/shift/multiply ops.

- `inst[31:28] = class`
- `inst[27:24] = op`
- `inst[23:20] = rd`
- `inst[19:16] = rs1`
- `inst[15:12] = rs2`
- `inst[11:0] = ext12` (must be zero in v0)

### 3.2 I16 Form (register + immediate)

Used by class `0x1` and class `0x2`.

- `inst[31:28] = class`
- `inst[27:24] = op`
- `inst[23:20] = rd`
- `inst[19:16] = rs1`
- `inst[15:0] = imm16`

`imm16` extension depends on instruction semantics: sign-extended for `ADDI`, zero-extended for `ANDI`/`ORI`/`XORI`.

### 3.3 S16-split Form (store)

Used by class `0x3`.

- `inst[31:28] = class`
- `inst[27:24] = op`
- `inst[23:20] = imm16[15:12]`
- `inst[19:16] = rs1`
- `inst[15:12] = rs2`
- `inst[11:0] = imm16[11:0]`

Reconstruction:
- `imm16 = {inst[23:20], inst[11:0]}`
- Effective address: `rs1 + sext(imm16)`

### 3.4 B16-split Form (branch)

Used by class `0x4`.

- `inst[31:28] = class`
- `inst[27:24] = op`
- `inst[23:20] = off16[15:12]`
- `inst[19:16] = rs1`
- `inst[15:12] = rs2`
- `inst[11:0] = off16[11:0]`

Reconstruction:
- `off16 = {inst[23:20], inst[11:0]}`
- Target: `pc + (sext(off16) << 2)`

For `B` (unconditional branch), `rs1` and `rs2` must be `0`.

### 3.5 J20 Form (relative jump/call/LPC)

Used by `JAL` (class `0x5`, op `0x0`) and `LPC` (class `0x5`, op `0x2`).

- `inst[31:28] = 0x5`
- `inst[27:24] = op` (`0x0` for `JAL`, `0x2` for `LPC`)
- `inst[23:20] = rd`
- `inst[19:0] = off20`

Computed value:
- `pc + (sext(off20) << 2)`
- `JAL`: stores `pc+4` in `rd`, branches to computed value.
- `LPC`: stores computed value in `rd`, does not branch.

### 3.6 JR16 Form (register jump)

Used by `JALR` (class `0x5`, op `0x1`).

- `inst[31:28] = 0x5`
- `inst[27:24] = 0x1`
- `inst[23:20] = rd`
- `inst[19:16] = rs1`
- `inst[15:0] = off16`

Target:
- `tmp = rs1 + sext(off16)`
- `pc = tmp & ~3`

## 4) Opcode Tables

### 4.1 Class `0x0` (ALU-R / Shift-R / Multiply)

- `op=0x0`: `NOP` only when full word is `0x00000000` (otherwise illegal)
- `op=0x1`: `ADD rd, rs1, rs2`
- `op=0x2`: `SUB rd, rs1, rs2`
- `op=0x3`: `AND rd, rs1, rs2`
- `op=0x4`: `OR rd, rs1, rs2`
- `op=0x5`: `XOR rd, rs1, rs2`
- `op=0x6`: `SLT rd, rs1, rs2`
- `op=0x7`: `SLTU rd, rs1, rs2`
- `op=0x8`: `SLL rd, rs1, rs2`
- `op=0x9`: `SRL rd, rs1, rs2`
- `op=0xA`: `SRA rd, rs1, rs2`
- `op=0xB`: `MUL rd, rs1, rs2`
- `op=0xC`: `MULH rd, rs1, rs2`
- `op=0xD`: `MULHU rd, rs1, rs2`
- `op=0xE`: `MULHSU rd, rs1, rs2`
- `op=0xF`: reserved

Constraint:
- For class `0x0`, `ext12` must be zero in v0.

### 4.2 Class `0x1` (ALU-I / Shift-I / LUI)

- `op=0x0`: `ADDI rd, rs1, imm16` (sign-extended)
- `op=0x1`: `ANDI rd, rs1, imm16` (zero-extended)
- `op=0x2`: `ORI rd, rs1, imm16` (zero-extended)
- `op=0x3`: `XORI rd, rs1, imm16` (zero-extended)
- `op=0x4`: `LUI rd, imm16` (`rs1` must be `0`)
- `op=0x5`: `SLLI rd, rs1, shamt5` (`imm16[15:5]` must be zero)
- `op=0x6`: `SRLI rd, rs1, shamt5` (`imm16[15:5]` must be zero)
- `op=0x7`: `SRAI rd, rs1, shamt5` (`imm16[15:5]` must be zero)
- `op=0x8..0xF`: reserved

### 4.3 Class `0x2` (Load)

- `op=0x0`: `LB rd, imm16(rs1)`
- `op=0x1`: `LBU rd, imm16(rs1)`
- `op=0x2`: `LH rd, imm16(rs1)`
- `op=0x3`: `LHU rd, imm16(rs1)`
- `op=0x4`: `LW rd, imm16(rs1)`
- `op=0x5..0xF`: reserved

### 4.4 Class `0x3` (Store)

- `op=0x0`: `SB rs2, imm16(rs1)`
- `op=0x1`: `SH rs2, imm16(rs1)`
- `op=0x2`: `SW rs2, imm16(rs1)`
- `op=0x3..0xF`: reserved

### 4.5 Class `0x4` (Branch)

- `op=0x0`: `B off16` (requires `rs1=0`, `rs2=0`)
- `op=0x1`: `BE rs1, rs2, off16`
- `op=0x2`: `BNE rs1, rs2, off16`
- `op=0x3`: `BLT rs1, rs2, off16`
- `op=0x4`: `BLTU rs1, rs2, off16`
- `op=0x5..0xF`: reserved

### 4.6 Class `0x5` (Jump/Call/LPC)

- `op=0x0`: `JAL rd, off20`
- `op=0x1`: `JALR rd, rs1, off16`
- `op=0x2`: `LPC rd, off20` (J20 form)
- `op=0x3..0xF`: reserved

Alias:
- `RET` = `JALR 0, 15, 0`

## 5) Explicit Architectural Rules

### 5.1 Register `0` Write Behavior

- Register `0` is hardwired to zero. Reads from `r0` always return `0x00000000`.
- When any instruction specifies `rd = 0`, the instruction **executes normally** — all side effects (memory reads/writes, address computation, `pc` updates for jumps) proceed as specified. Only the register writeback to `r0` is silently discarded.
- This means `JAL 0, offset` still branches and computes `pc + 4`, but does not store the link address. `LW 0, imm16(rs1)` still performs the memory read (and may raise a fault on misaligned/unmapped address), but discards the loaded value.

### 5.2 Instruction Side Effects Beyond `rd`

- **Loads** (`LB`, `LBU`, `LH`, `LHU`, `LW`): always perform the memory read at the computed address. The read may trigger implementation-defined behavior on unmapped or misaligned addresses regardless of `rd`.
- **Stores** (`SB`, `SH`, `SW`): always perform the memory write. The `rs2` value is the data written; there is no `rd` in store instructions.
- **Jump-and-link** (`JAL`, `JALR`): always update `pc` to the target. The link address `pc + 4` is written to `rd` (discarded if `rd = 0`).
- **LPC**: computes the PC-relative address and writes it to `rd`. No control flow change. If `rd = 0`, the address is discarded.
- **Branches** (`B`, `BE`, `BNE`, `BLT`, `BLTU`): no `rd`. Condition is evaluated and `pc` is updated accordingly.
- **NOP**: no side effects beyond `pc = pc + 4`.

### 5.3 Arithmetic Behavior

- All integer arithmetic (`ADD`, `SUB`, `ADDI`, `MUL`, etc.) uses wraparound two's-complement semantics. There is no overflow trap or overflow flag.
- There are **no internal condition flags** (`OV`, `Z`, carry, etc.) in this ISA. All conditional control flow is via register-compare branches.

### 5.4 Shift Amount Masking

- Register shifts (`SLL`, `SRL`, `SRA`) use only `rs2[4:0]` as the shift amount (0–31).
- Immediate shifts (`SLLI`, `SRLI`, `SRAI`) use a 5-bit `shamt5` field; bits `imm16[15:5]` must be zero (otherwise illegal).

## 6) Illegal Encoding Rules (v0)

Illegal instruction if any condition is met:
1. Class is reserved (`0x6..0xF`).
2. Opcode is reserved within a valid class.
3. Class `0x0`, op `0x0` is used with any nonzero payload (only exact `0x00000000` is valid `NOP`).
4. Class `0x0` instructions use nonzero `ext12`.
5. `LUI` has `rs1 != 0`.
6. Shift-immediate instructions have nonzero `imm16[15:5]`.
7. `B` uses nonzero `rs1` or `rs2`.

## 7) Canonical Encodings (Examples)

- `NOP` = `0x00000000`
- `RET` = `0x510F0000` (`JALR 0, 15, 0`)
- `B 1` = `0x40000001`
- `B 0` = `0x40000000` (`B .`, canonical halt loop)
- `BE 1, 2, -4` = `0x41F12FFC`

## 8) Notes on ISA Identity

This encoding intentionally differs from RISC-V encoding style:
1. Custom split opcode classes/op map.
2. Fixed `0..15` register tokens in assembly surface.
3. Custom branch vocabulary (`B`, `BE`, `BNE`, `BLT`, `BLTU`).
4. No condition flags — all branches are register-compare or unconditional.
5. Permanent all-zero `NOP` reservation.
6. Zero-extending bitwise immediates (`ANDI`/`ORI`/`XORI`) vs. sign-extending arithmetic immediate (`ADDI`).
7. PC-relative address forming (`LPC`) in the jump/call class.
8. Explicit r0-write-discard semantics (instruction still executes, only writeback is suppressed).
