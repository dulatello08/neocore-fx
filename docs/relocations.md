# NeoCoreFX Relocation & Label Materialization Rules

Status: v0.5 companion document
Parent: [isa-v0.md](isa-v0.md)

## 1) Overview

NeoCoreFX uses a **two-pass** toolchain model: the assembler emits relocatable object files, and the linker resolves addresses and patches instruction fields. This document defines the relocation types, how constants and labels become machine-encodable values, and the rules the linker must follow.

## 2) Address Model

- All addresses are 32-bit byte addresses.
- Instructions are 4-byte aligned (`addr[1:0] == 0`).
- The ISA uses **PC-relative** offsets for branches (`off16`), jumps (`off20`), and `LPC` (`off20`). See [pc-relative.md](pc-relative.md) for exact semantics.
- Absolute addresses are formed via `LUI` + `ORI` (two instructions, no PC-relative component).

## 3) Relocation Types

### 3.1 `R_NCFX_ABS_HI16`

- **Applies to**: `LUI rd, imm16` instruction.
- **Field**: `imm16` (bits `[15:0]` of the I16-form encoding).
- **Computation**: `(S + A) >> 16` where `S` = symbol value, `A` = addend.
- **Semantics**: extracts the upper 16 bits of the target absolute address.

### 3.2 `R_NCFX_ABS_LO16`

- **Applies to**: `ORI rd, rs1, imm16` instruction (in `LUI`+`ORI` pair).
- **Field**: `imm16` (bits `[15:0]` of the I16-form encoding).
- **Computation**: `(S + A) & 0xFFFF`.
- **Semantics**: extracts the lower 16 bits. Because `ORI` zero-extends, this combines cleanly with `LUI` — no sign-correction needed (unlike RISC-V `LUI`+`ADDI`).

### 3.3 `R_NCFX_PC_REL16`

- **Applies to**: branch instructions (`B`, `BE`, `BNE`, `BLT`, `BLTU`) using B16-split form.
- **Field**: `off16` (split across `inst[23:20]` and `inst[11:0]`).
- **Computation**: `((S + A) - P) >> 2` where `P` = address of the instruction being relocated.
- **Range**: signed 16-bit word offset → byte range `[pc - 131072, pc + 131068]` (±128 KiB).
- **Overflow**: linker must error if the result does not fit in a signed 16-bit value.

### 3.4 `R_NCFX_PC_REL20`

- **Applies to**: `JAL rd, off20` and `LPC rd, off20` using J20 form.
- **Field**: `off20` (bits `[19:0]`).
- **Computation**: `((S + A) - P) >> 2`.
- **Range**: signed 20-bit word offset → byte range `[pc - 2097152, pc + 2097148]` (±2 MiB).
- **Overflow**: linker must error if the result does not fit in a signed 20-bit value.

### 3.5 `R_NCFX_PC_REL16_S` (store-offset, load-offset)

- **Applies to**: `ADDI rd, rs1, imm16` and load/store instructions when used with a PC-relative base from `LPC`.
- **Field**: `imm16` (bits `[15:0]`).
- **Computation**: `((S + A) - P_lpc) & 0xFFFF` — but note this is relative to the `LPC` instruction's address, not the consuming instruction's address. Requires paired relocation with the `LPC`.
- **Status**: deferred — v0 toolchain uses absolute addressing for data. PC-relative data access patterns will be defined when needed.

## 4) Label Materialization Patterns

### 4.1 Near Code Label (within ±128 KiB)

Used for branch targets.

```asm
    BNE 1, 2, target    ; R_NCFX_PC_REL16, resolved by linker
```

### 4.2 Near Code Label (within ±2 MiB)

Used for jump/call targets.

```asm
    JAL 15, target       ; R_NCFX_PC_REL20, resolved by linker
```

### 4.3 Absolute 32-bit Address

Used for data pointers, function pointers, or far code addresses.

```asm
    LUI  rd, %hi(target)   ; R_NCFX_ABS_HI16
    ORI  rd, rd, %lo(target) ; R_NCFX_ABS_LO16
```

Assembler syntax `%hi()` and `%lo()` extract the upper and lower 16 bits respectively. The assembler emits the appropriate relocation records.

### 4.4 PC-Relative Address (within ±2 MiB)

Used for position-independent data references.

```asm
    LPC rd, target       ; R_NCFX_PC_REL20 — rd = pc + (sext(off20) << 2)
```

For data at a known small offset from the `LPC`:
```asm
    LPC  rd, data_base   ; rd = address of data_base
    LW   rt, offset(rd)  ; load from data_base + offset
```

## 5) Constant Rules

### 5.1 Immediate Encoding

- **Signed immediates** (`ADDI`, branch offsets, jump offsets, load/store offsets): the assembler must verify the value fits in the signed range of the field width.
- **Unsigned immediates** (`ANDI`, `ORI`, `XORI`): the assembler must verify `0 ≤ value ≤ 0xFFFF`. Negative values in source must be rejected or explicitly cast.
- **`LUI` immediate**: treated as a raw 16-bit pattern (no sign interpretation). The value `0x0000..0xFFFF` maps to the upper halfword.

### 5.2 Assembler Constant Expressions

- The assembler should support constant expressions in operand positions: `ADDI 1, 0, (4 * 8)`.
- Expressions involving labels produce relocatable values and must follow the relocation rules above.
- Expressions mixing absolute and relocatable terms follow standard linker algebra: `(label - label)` is absolute, `(label + constant)` is relocatable.

## 6) Object File Format

- Deferred to toolchain documentation. The relocation types above are defined independently of container format.
- Expected format: simple custom binary or ELF-like with section headers, symbol table, and relocation table.
