# NeoCoreFX Far Branch & Far Call Expansion

Status: v0.5 companion document
Parent: [isa-v0.md](isa-v0.md)

## 1) The Problem

NeoCoreFX has fixed-width 32-bit instructions with limited displacement fields:

| Instruction class | Offset field | Word range | Byte range |
|---|---|---|---|
| Branches (`B`, `BE`, `BNE`, `BLT`, `BLTU`) | `off16` (signed) | ±32768 words | **±128 KiB** |
| Jumps (`JAL`, `LPC`) | `off20` (signed) | ±524288 words | **±2 MiB** |
| Register jump (`JALR`) | `off16` (signed) + register | full 32-bit space | **4 GiB** |

When a target label is beyond the range of the displacement field, the assembler (or linker) must expand the instruction into a multi-instruction sequence. This is called **far branching** or **range extension**.

## 2) Expansion Strategies

### 2.1 Far Unconditional Branch

**Near** (fits in `off16`):
```asm
    B target                ; single instruction
```

**Medium** (fits in `off20` but not `off16`):
```asm
    JAL 0, target           ; use J20 form, discard link (rd=0)
```

**Far** (exceeds `off20`):
```asm
    LUI  1, %hi(target)    ; r1 = assembler temporary
    ORI  1, 1, %lo(target)
    JALR 0, 1, 0            ; jump, discard link
```
- Clobbers `r1` (assembler temporary `at`).
- 3 instructions, 12 bytes.

### 2.2 Far Conditional Branch

Conditional branches only have `off16` range. Far conditional branches use an **inversion + trampoline** pattern:

**Near** (fits in `off16`):
```asm
    BNE 1, 2, target       ; single instruction
```

**Medium** (fits in `off20` but not `off16`):
```asm
    BE  1, 2, .skip        ; invert condition, skip over jump
    JAL 0, target           ; unconditional far jump (J20 form)
.skip:
```
- 2 instructions, 8 bytes.
- The branch condition is **inverted**: `BNE` becomes `BE`, `BLT` becomes `BGE` (which is itself a pseudo — use `BLT rs2, rs1` or `SLT` + `BE`).

**Far** (exceeds `off20`):
```asm
    BE  1, 2, .skip        ; invert condition
    LUI  1, %hi(target)
    ORI  1, 1, %lo(target)
    JALR 0, 1, 0
.skip:
```
- 4 instructions, 16 bytes.
- Clobbers `r1` (`at`).

### 2.3 Far Call (`CALL label`)

**Near** (fits in `off20`):
```asm
    JAL 15, target          ; link to r15
```

**Far** (exceeds `off20`):
```asm
    LUI  1, %hi(target)    ; r1 = assembler temporary
    ORI  1, 1, %lo(target)
    JALR 15, 1, 0           ; call, link address in r15
```
- 3 instructions, 12 bytes.
- Clobbers `r1` (`at`).
- `r15` gets `pc + 4` of the `JALR`, which is the correct return point.

### 2.4 Far Return

`RET` (`JALR 0, 15, 0`) is always single-instruction because it uses register-indirect addressing. No far expansion needed.

## 3) Condition Inversion Table

When a conditional branch must be expanded to a far branch, the condition is inverted:

| Original | Inverted |
|---|---|
| `BE rs1, rs2` | `BNE rs1, rs2` |
| `BNE rs1, rs2` | `BE rs1, rs2` |
| `BLT rs1, rs2` | `BLT rs2, rs1` then negate — see note |
| `BLTU rs1, rs2` | `BLTU rs2, rs1` then negate — see note |

**Note on `BLT`/`BLTU` inversion**: The true inverse of `BLT rs1, rs2` is `BGE rs1, rs2` (branch if `rs1 >= rs2`). Since `BGE` is not a hardware instruction, the assembler must use: skip with `BLT rs1, rs2, .skip` (non-inverted, short forward branch over the trampoline). The pattern becomes:

```asm
    ; Original: BLT rs1, rs2, far_target
    ; Expanded:
    BLT rs1, rs2, .do_jump   ; original condition, jump to trampoline
    B .skip                   ; fall through = condition false
.do_jump:
    JAL 0, far_target         ; or LUI/ORI/JALR for truly far
.skip:
```

Alternative (more compact for medium range):
```asm
    ; Equivalent but avoids double branch:
    SLT at, rs1, rs2         ; at = (rs1 < rs2) ? 1 : 0
    BE  at, 0, .skip         ; if not less-than, skip
    JAL 0, far_target
.skip:
```

## 4) Expansion Policy

### 4.1 When Expansion Happens

- **Assembler-time**: if the target label is in the same translation unit and the assembler can compute the offset, it performs expansion during assembly.
- **Linker-time**: if the target is in a different object file, the assembler emits a relocation. The linker checks range and either patches the instruction directly or inserts a **linker-generated trampoline** (veneer).

### 4.2 Linker Veneers

- If the linker determines a PC-relative relocation overflows, it **must** insert a veneer (trampoline stub) and redirect the original branch/jump to the veneer.
- Veneers are placed in a linker-generated section (e.g., `.text.veneer`).
- Each veneer is a 3-instruction sequence: `LUI 1, hi` / `ORI 1, 1, lo` / `JALR {0|15}, 1, 0`.
- Veneers clobber `r1` (`at`). The ABI must ensure `r1` is not live across calls.
- The linker should deduplicate veneers: if multiple call sites target the same far function, they can share a single veneer.

### 4.3 Assembler Temporary Clobbering

- Any far expansion that uses `r1` (`at`) **must** be flagged in assembler diagnostics if the programmer has explicitly referenced `r1` in the same basic block.
- In the absence of linker veneer support, the assembler must reject programs that require far branches/calls to external symbols unless the programmer uses explicit `LUI`/`ORI`/`JALR` sequences.

## 5) Range Summary

| Scenario | Instructions | Bytes | Clobbers |
|---|---|---|---|
| Near branch (±128 KiB) | 1 | 4 | none |
| Medium branch (±2 MiB) | 2 | 8 | none |
| Far branch (full 32-bit) | 3–4 | 12–16 | `r1` (`at`) |
| Near call (±2 MiB) | 1 | 4 | none |
| Far call (full 32-bit) | 3 | 12 | `r1` (`at`) |
| Return | 1 | 4 | none |
