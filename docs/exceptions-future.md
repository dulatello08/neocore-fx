# NeoCoreFX Exception Model — Future Entry Point

Status: v0.5 placeholder — **no exceptions are implemented in v0**
Parent: [isa-v0.md](isa-v0.md)

## 1) Current State (v0)

- **No interrupts**. No interrupt controller, no interrupt enable/disable, no interrupt vector table.
- **No privilege levels**. All code runs at a single privilege level.
- **No CSRs**. No control/status register surface (no `mstatus`, `mcause`, `mepc` equivalents).
- **No trap instructions**. No `ECALL`, `EBREAK`, `WFI`, or similar.

The following conditions are **detectable** by hardware but have **implementation-defined** responses in v0:

| Condition | Detection | v0 Response |
|---|---|---|
| Illegal instruction | Decode-time | Implementation-defined (may halt, may skip) |
| Instruction address misalignment | Fetch-time | Implementation-defined |
| Data address misalignment | Execute/memory-time | Architecturally undefined |
| Unmapped memory access | Memory-time | Implementation-defined |

## 2) Design Direction for v1+

This section outlines the **intended direction** for the exception model. Nothing here is frozen — it exists to guide ISA design decisions in v0 so they don't paint us into a corner.

### 2.1 Exception Classes (Planned)

| Class | Priority | Examples |
|---|---|---|
| **Reset** | Highest | Power-on, external reset |
| **Machine fault** | High | Illegal instruction, address fault |
| **External interrupt** | Medium | Timer, I/O device |
| **Software trap** | Low | Explicit `ECALL`/`EBREAK` |

### 2.2 Trap State Registers (Sketch)

Minimal set, inspired by RISC-V M-mode but simplified:

| Register | Name | Purpose |
|---|---|---|
| `epc` | Exception PC | PC of the faulting/trapping instruction |
| `ecause` | Exception cause | Encoded reason for the trap |
| `eval` | Exception value | Faulting address or instruction word |
| `estatus` | Exception status | Interrupt enable, prior state |
| `evec` | Exception vector | Base address of trap handler |

Access mechanism: dedicated CSR-like instructions or memory-mapped registers (TBD).

### 2.3 Entry/Exit Sequence (Sketch)

**On exception**:
1. `epc ← pc` of faulting instruction.
2. `ecause ← encoded cause`.
3. `eval ← relevant value` (e.g., bad address).
4. `estatus ← save prior interrupt-enable state, then disable interrupts`.
5. `pc ← evec` (jump to handler).

**Return from exception**:
- Dedicated `ERET` instruction: `pc ← epc`, restore `estatus`.
- Alternatively, `JALR` to `epc` with manual status restore (less clean but doesn't require a new instruction).

### 2.4 Encoding Space Reserved

- ISA class `0x6..0xF` are reserved in v0. The exception/system instructions will be allocated from this space.
- Candidate class: `0x6` for system/CSR instructions.
- This means v0 programs that avoid class `0x6..0xF` will remain forward-compatible.

## 3) v0 Constraints That Support Future Exceptions

The following v0 design choices were made with future exceptions in mind:

1. **Reserved encoding classes** (`0x6..0xF`): plenty of opcode space for system instructions.
2. **Illegal instruction detection**: v0 hardware should detect (but may not cleanly handle) illegal encodings. This gives us a fault source when exceptions are added.
3. **`JALR` with `rd=0`**: can be used as a primitive "jump to handler" even without dedicated exception instructions.
4. **Link register convention** (`r15`): exception handlers can use `JAL`/`JALR` normally.
5. **No hardwired stack pointer**: `r13` as SP is ABI-only, so exception handlers can use their own stack without conflicting with ISA-level mechanisms.
6. **`pc` is well-defined**: every instruction has a single, unambiguous `pc` value, which is what `epc` will capture.

## 4) Open Questions for v1

1. **Vectored vs. direct handler**: should `evec` be a table base or a single entry point?
2. **Nested exceptions**: allow or forbid? If allowed, how deep?
3. **Interrupt priority**: flat or multi-level?
4. **CSR access mechanism**: dedicated instructions (like RISC-V `csrrw`) or memory-mapped registers?
5. **Privilege levels**: single level (M-mode only) or M+U split?
6. **Debug mode**: separate from exceptions or integrated?
7. **NMI**: non-maskable interrupt support?

## 5) Guidance for v0 Toolchain/Software

- Do **not** generate code in classes `0x6..0xF`.
- Do **not** assume any behavior on illegal instruction execution — the response is implementation-defined.
- Do **not** rely on interrupt-driven I/O — use polling.
- Code should be written to be **exception-safe** where possible (avoid data structures left in inconsistent states by sudden transfer of control), as this will ease the transition to v1.
