# NeoCoreFX PC-Relative Semantics

Status: v0.5 companion document
Parent: [isa-v0.md](isa-v0.md)

## 1) Definition of `pc` for Offset Computation

For all PC-relative instructions, `pc` is the address of **the instruction itself** (the instruction currently being executed), not `pc + 4` or any other value.

Formally: if the instruction is located at byte address `A`, then `pc = A` in the offset formula.

## 2) PC-Relative Instructions

### 2.1 Branches: `B`, `BE`, `BNE`, `BLT`, `BLTU`

```
target_address = pc + (sext(off16) << 2)
```

- `off16` is a signed 16-bit word offset extracted from the B16-split encoding.
- The `<< 2` converts the word offset to a byte offset (since instructions are 4-byte aligned).
- **Range**: `pc - 131072` to `pc + 131068` (byte addresses), i.e., ±128 KiB relative to the branch instruction.
- **Self-branch**: `off16 = 0` means `target = pc`, creating an infinite loop. This is a legal encoding and is the canonical `HALT` alias (`B .`) in the current RTL.
- **Next instruction**: `off16 = 1` means `target = pc + 4`, which is a no-op branch (falls through to next instruction). Legal but pointless for conditional branches.

### 2.2 `JAL rd, off20`

```
link = pc + 4
target_address = pc + (sext(off20) << 2)
rd = link
pc = target_address
```

- `off20` is a signed 20-bit word offset from the J20 encoding.
- Link address is always `pc + 4` (the instruction after the `JAL`), regardless of whether the jump is taken.
- **Range**: `pc - 2097152` to `pc + 2097148` (byte addresses), i.e., ±2 MiB.
- **Self-call**: `off20 = 0` → `target = pc`, `rd = pc + 4`. Creates an infinite loop but the link register gets a useful value (one past the JAL). This pattern is unusual but legal.

### 2.3 `LPC rd, off20`

```
rd = pc + (sext(off20) << 2)
pc = pc + 4   (normal advance, no branch)
```

- Same offset encoding as `JAL` (J20 form, signed 20-bit word offset).
- **Does not branch**. The `pc` advances normally to `pc + 4`.
- Primary use: compute the address of a nearby data or code label and place it in a register for later use (e.g., as a base pointer for loads/stores).
- **Range**: same as `JAL`, ±2 MiB.
- **`LPC rd, 0`**: `rd = pc` — loads the address of the `LPC` instruction itself.
- **`LPC rd, 1`**: `rd = pc + 4` — loads the address of the next instruction.

### 2.4 `JALR rd, rs1, off16`

```
tmp = rs1 + sext(off16)
link = pc + 4
rd = link
pc = tmp & ~3
```

- `JALR` is **not** PC-relative in its target computation — the target comes from `rs1 + sext(off16)`.
- However, the **link address** `pc + 4` is PC-relative (it's the return point).
- The `& ~3` forces word alignment of the target (clears bottom 2 bits).

## 3) Assembler Offset Computation

When the assembler encounters a branch or jump with a label operand, it computes the offset as:

```
word_offset = (label_address - instruction_address) >> 2
```

This value is what gets encoded into `off16` or `off20`. The division by 4 (right-shift by 2) converts the byte distance to a word distance.

**Example**:
```asm
        ; instruction at address 0x1000
loop:   ADD 1, 1, 2          ; 0x1000
        ADDI 3, 3, 1         ; 0x1004
        BNE 3, 4, loop       ; 0x1008, target = 0x1000
        ; word_offset = (0x1000 - 0x1008) >> 2 = (-8) >> 2 = -2
        ; off16 = -2 (0xFFFE in 16-bit signed)
```

**Verification**: `pc + (sext(-2) << 2) = 0x1008 + (-8) = 0x1000` ✓

## 4) Alignment Invariants

- All instruction addresses are 4-byte aligned. The assembler and linker must guarantee this.
- Branch and jump targets are always 4-byte aligned by construction (the `<< 2` in the formula ensures this).
- `JALR` explicitly masks with `& ~3` to force alignment even when `rs1 + off16` might be misaligned.
- If an instruction fetch occurs at a misaligned address, the behavior is architecturally undefined (likely implementation trap).

## 5) Position-Independent Code (PIC) Patterns

### 5.1 PC-Relative Data Access

```asm
    LPC  rd, data_label     ; rd = address of data_label (within ±2 MiB)
    LW   rt, 0(rd)          ; load from data_label
```

For data at a fixed offset from a base:
```asm
    LPC  rd, data_base      ; rd = base address
    LW   rt, 8(rd)          ; load from data_base + 8
    SW   ru, 12(rd)         ; store to data_base + 12
```

### 5.2 PC-Relative Function Call

For calls within ±2 MiB:
```asm
    JAL  15, function       ; direct PC-relative call
```

For position-independent far calls:
```asm
    LPC  rd, got_entry      ; rd = address of GOT entry (if using GOT)
    LW   rd, 0(rd)          ; rd = actual function address
    JALR 15, rd, 0          ; indirect call
```

### 5.3 Getting Current PC

```asm
    LPC  rd, 0              ; rd = address of this LPC instruction
    ; or
    LPC  rd, 1              ; rd = address of next instruction (pc + 4)
```

## 6) Interaction with Linker Relaxation

- The linker may **relax** long-range sequences into shorter ones if it determines the target is within range after final layout.
- Example: a far call sequence (`LUI`/`ORI`/`JALR`) may be relaxed to `JAL` + `NOP` + `NOP` (maintaining alignment and size) or to `JAL` alone if the section can be compacted.
- Relaxation is optional and implementation-defined in v0.
