# NeoCoreFX Microarchitecture

Status: v0.5 companion document — initial 6-stage pipeline design
Parent: [isa-v0.md](isa-v0.md)

## 1) Pipeline Overview

NeoCoreFX v0 implements a **single-issue, in-order, 6-stage pipeline** targeting high clock frequency on Lattice ECP5.

| Stage | Name | Primary Function |
|-------|------|-----------------|
| **IF1** | Instruction Fetch 1 | PC generation, branch prediction, I-Bus address driven |
| **IF2** | Instruction Fetch 2 | Instruction word arrives from BRAM (1-cycle latency absorbed) |
| **ID** | Instruction Decode | Decode, register file read, immediate extraction, hazard detection |
| **EXE** | Execute | ALU operation, branch resolution, load/store address computation |
| **MEM** | Memory Access | D-Bus transaction for loads/stores (BRAM: 1-cycle ack) |
| **WB** | Writeback | Result written to register file, halt retirement detection |

Design principle: each stage boundary is a pipeline register. Every stage has at most one major operation (one BRAM read, one ALU op, one register file access) to keep combinational depth short and frequency high.

## 2) Stage-by-Stage Detail

### 2.1 IF1 — Instruction Fetch 1

**Inputs**: PC register, branch prediction, redirect from EXE (on mispredict).

**Operations**:
- Select next PC from one of:
  1. `pc + 4` (sequential, default).
  2. Branch target from predictor (predicted-taken branch).
  3. Redirect target from EXE (mispredict correction — highest priority).
- Drive I-Bus with selected PC: `ibus_addr = next_pc`, assert `ibus_cyc`, `ibus_stb`.
- Apply static **BTFNT** (Backward Taken, Forward Not Taken) prediction. The branch target is computed from the instruction in IF2/ID — see §3 for details.
- Update PC register with selected next PC.

**Pipeline register IF1→IF2 contents**:
- `pc` (address of the instruction being fetched).
- `predicted_taken` (1-bit: was this fetch the result of a predicted-taken branch?).

**Timing note**: the BIU I-Port path must be combinational here — `next_pc` feeds directly to `ibus_addr` with no intervening register. The BRAM sees the address this cycle and registers the output internally, delivering data at the IF2 boundary.

### 2.2 IF2 — Instruction Fetch 2

**Inputs**: BRAM read data (`ibus_rdata`), I-Bus ack/err.

**Operations**:
- Latch the 32-bit instruction word arriving from BRAM.
- If `ibus_err`: mark instruction as faulting (illegal fetch address). This propagates down the pipeline and triggers implementation-defined behavior when it reaches WB.
- No decode happens here — this stage exists purely to absorb BRAM latency and keep the IF1 combinational path short.

**Pipeline register IF2→ID contents**:
- `pc` (forwarded from IF1→IF2).
- `inst` (32-bit instruction word).
- `predicted_taken` (forwarded).
- `fetch_fault` (1-bit: I-Bus returned error).

### 2.3 ID — Instruction Decode

**Inputs**: instruction word, PC, register file.

**Operations**:
- Decode instruction fields: `class`, `op`, `rd`, `rs1`, `rs2`, immediate (sign-extend or zero-extend per instruction type).
- Read register file: two read ports, addressed by `rs1` and `rs2`. Reads are combinational (result available within this cycle).
- Detect data hazards and select forwarding sources. If a load-use hazard exists that cannot be resolved by forwarding, assert **stall** to IF1 and IF2 (see §5).
- Extract all control signals: ALU operation, memory access type, register write enable, branch type, etc.

**Pipeline register ID→EXE contents**:
- `pc`, `rd`, `rs1_data`, `rs2_data`, `immediate`.
- `rs1_addr`, `rs2_addr` (needed by EXE-stage forwarding mux).
- Control signals: `alu_op`, `alu_src` (register vs immediate), `mem_read`, `mem_write`, `mem_size`, `reg_write`, `branch_type`, `is_jump`, `is_lui`, `is_lpc`.
- Control flags include `is_halt` for the canonical halt alias (`B .`).
- `predicted_taken` (forwarded).
- `fetch_fault` (forwarded).
- `is_halt` (forwarded when decode recognizes `B .`).
- **Forwarding select signals**: `fwd_rs1_sel`, `fwd_rs2_sel` (see §5.3).

### 2.4 EXE — Execute

**Inputs**: register data (possibly overridden by forwarding mux), immediate, control signals.

**Operations**:
- **Forwarding mux**: before the ALU, `rs1_data` and `rs2_data` are passed through a forwarding mux that may substitute values from MEM or WB (see §5.3). This is the final operand selection.
- **ALU**: compute result based on `alu_op`. Inputs are `rs1_final` and either `rs2_final` or `immediate` (selected by `alu_src`). Operations: add, sub, and, or, xor, slt, sltu, sll, srl, sra.
- **Branch resolution**: evaluate branch condition (`BE`, `BNE`, `BLT`, `BLTU`) by comparing `rs1_final` and `rs2_final`. Compare result against `predicted_taken`. If mismatch → **mispredict detected** → send redirect to IF1 and flush IF2 + ID.
- **Load/store address**: compute effective address `rs1_final + sext(imm16)` (this is just an ADD, shares the ALU or uses a dedicated adder).
- **Jump target**: for `JAL`, target is `pc + (sext(off20) << 2)`. For `JALR`, target is `(rs1_final + sext(off16)) & ~3`. Link value is `pc + 4`.
- **LPC result**: `pc + (sext(off20) << 2)`, no branch.
- **LUI result**: `imm16 << 16`.
- **Multiply**: `MUL`/`MULH`/`MULHU`/`MULHSU` — result computed here. If the multiplier cannot complete in 1 cycle, it stalls (see §7).

**Pipeline register EXE→MEM contents**:
- `exe_result` (ALU result, jump link value, LUI result, or LPC result — muxed by instruction type).
- `store_data` (rs2_final, for store instructions — already lane-shifted by BIU or shifted in MEM).
- `rd`, `rd_we` (will this instruction write a register?).
- `mem_read`, `mem_write`, `mem_size`.
- `fetch_fault` (forwarded).

**Side effects**:
- Branch redirect signal to IF1 (combinational, not registered — must act immediately).
- Flush signal to IF2 and ID pipeline registers (turns instructions in those stages into bubbles).

### 2.5 MEM — Memory Access

**Inputs**: EXE result (memory address for loads/stores), store data, control signals.

**Operations**:
- **Store data forwarding**: for stores, the data to be written (`store_data`) may be overridden by a forward from WB if the preceding instruction is writing the same register (see §5.4 MEM-stage store forwarding).
- If `mem_read` or `mem_write`: drive D-Bus via BIU. Address = `exe_result`. For stores, data comes from `store_data` (lane-shifted and byte-selected by the BIU based on `mem_size` and address LSBs).
- If D-Bus does not ack in 1 cycle (slow peripheral, SDRAM): **stall the entire pipeline** until `dbus_ack` or `dbus_err`.
- For non-memory instructions: this stage is a pass-through (`exe_result` flows to WB).

**Pipeline register MEM→WB contents**:
- `wb_data`: either `exe_result` (for ALU/jump/LUI/LPC instructions) or loaded data from D-Bus (for loads, byte/half extracted and zero/sign-extended by BIU).
- `rd`, `rd_we`.
- `mem_fault` (D-Bus returned error).
- `is_halt` (forwarded).

### 2.6 WB — Writeback

**Inputs**: `wb_data`, `rd`, `rd_we`.

**Operations**:
- If `rd_we` and `rd != 0`: write `wb_data` to register file at address `rd`.
- If `rd == 0`: write is silently discarded (r0 semantics), but any faults that propagated still occurred.
- Register file write port is active in this stage.
- If `is_halt` is set on a valid retiring instruction, assert `halted` to stop frontend/pipeline advancement.

### 2.7 HALT Alias (`B .`)

- Encoding: `B off16` with `off16 = 0`, assembly form `B .`.
- Decode stage marks this as `is_halt`.
- The bit is pipelined through EXE and MEM into WB.
- WB asserts `halted` when the instruction retires without fault/illegal kill.
- System integration rule: freeze IF/ID/EXE/MEM advancement once `halted` is observed.

## 3) Branch Prediction — Static BTFNT

### 3.1 Policy

**BTFNT** = Backward Taken, Forward Not Taken.

- **Backward branch** (negative offset, i.e., target address < branch address): predict **taken**. This handles loops — the back edge is taken almost every iteration.
- **Forward branch** (positive offset, i.e., target address > branch address): predict **not taken**. This handles error checks and early exits — the common path falls through.
- **Unconditional branches** (`B`): always taken (not a prediction, it's a fact).
- **Jumps** (`JAL`, `JALR`): always taken.

### 3.2 Prediction Timing

Prediction must happen **before** the instruction is decoded. In a 6-stage pipeline, the challenge is that the instruction word isn't available until IF2, but IF1 is already choosing the next PC.

**Approach**: prediction is made in IF2 (when the instruction is first available), and takes effect on the *next* IF1 cycle via a redirect signal. This means:

- A predicted-taken backward branch incurs a **1-cycle bubble** (IF1 was already fetching `pc+4`; it redirects on the next cycle).
- A not-taken prediction (forward branch, or no branch) has **zero penalty** — IF1 was already fetching `pc+4`.
- This is acceptable for static prediction — the cost of dynamic prediction hardware is not justified in v0.

### 3.3 Mispredict Penalty

Branch condition is evaluated in **EXE** (stage 4). If the prediction was wrong:

| Mispredict type | What happens | Penalty |
|---|---|---|
| Predicted taken, actually not taken | IF1, IF2, ID have wrong instructions | **3 cycles** (flush IF2, ID, squash EXE result) |
| Predicted not taken, actually taken | IF1, IF2, ID have wrong instructions | **3 cycles** |
| Unconditional jump (`JAL`) | Always taken, redirect from IF2 | **1 cycle** (IF1 had `pc+4`, redirect on next cycle) |
| `JALR` (register jump) | Target unknown until EXE (needs `rs1` value) | **3 cycles** |

### 3.4 Flush Mechanics

On mispredict detection in EXE:
1. **IF1**: receives correct target address from EXE; next cycle fetches from the right PC.
2. **IF2 pipeline register**: replaced with a bubble/NOP.
3. **ID pipeline register**: replaced with a bubble/NOP.
4. **EXE pipeline register**: the mispredicting instruction itself completes normally (e.g., `JAL` still writes its link register).

## 4) Register File

### 4.1 Port Requirements

- **2 read ports**: combinational reads in ID stage, addressed by `rs1` and `rs2`.
- **1 write port**: clocked write in WB stage, addressed by `rd`.
- **Read-during-write behavior**: if ID reads a register that WB is writing in the same cycle, the read must return the **new value** (write-first / bypass). This is either handled in the register file design or by explicit WB→ID forwarding.

### 4.2 r0 Handling

- Read port: `rs1 == 0` or `rs2 == 0` always returns `0x00000000`. Can be implemented as a mux on the read output or by never writing to entry 0.
- Write port: `rd == 0` write is ignored. Implemented by gating the write enable: `rf_we = rd_we & (rd != 4'b0000)`.

### 4.3 Implementation

On ECP5, the register file (16 × 32-bit, 2R1W) is small enough to implement in distributed logic (LUTs) rather than BRAM. This gives combinational read access, which is essential for the ID stage timing.

## 5) Data Hazards and Forwarding

### 5.1 Hazard Scenario

At any given cycle, the pipeline snapshot is:

| Stage | Instruction | Result status |
|---|---|---|
| WB | instr N-2 | Writing to register file **this cycle** |
| MEM | instr N-1 | Result available: `wb_data` (ALU result or load data) |
| EXE | instr N | Result being computed: `exe_result` (available at end of cycle) |
| ID | instr N+1 | **Needs** `rs1_data` and `rs2_data` — potential hazard source |
| IF2 | instr N+2 | Instruction word only, no register access |
| IF1 | instr N+3 | Address only |

Instr N+1 (in ID) reads registers that may be written by instrs N, N-1, or N-2. These are **RAW (Read After Write)** hazards.

### 5.2 Forwarding Architecture — Two-Point Forwarding

Forwarding is split across two stages to balance timing:

**Stage 1 — ID (early forwarding selection)**:
- ID detects which instructions ahead (in EXE, MEM, WB) will write a register matching `rs1` or `rs2`.
- ID selects forwarding source and encodes it as `fwd_rs1_sel` / `fwd_rs2_sel` control signals.
- If no hazard or if the value comes from register file / WB write-first, the register file read value is used.

**Stage 2 — EXE (late forwarding mux)**:
- The actual data mux lives at the **EXE stage inputs**, not in ID.
- The mux selects between: `rs_data` (from ID register read), `mem_fwd` (from MEM), or `wb_fwd` (from WB).
- Reason: the forwarded values from MEM and WB aren't available early enough in ID cycle to be routed through ID's combinational logic and into the ID→EXE register without creating a timing-critical path. By placing the mux at EXE's input, we give MEM→EXE and WB→EXE a full cycle of routing time.

### 5.3 Forwarding Paths — Complete Table

All forwarding paths, by source and destination:

| # | Path | Source data | When it helps | Condition |
|---|---|---|---|---|
| **F1** | EXE→EXE | `exe_result` from previous cycle's EXE (now in EXE→MEM register) | Back-to-back ALU: `ADD r1,..; ADD r2,r1,..` | `mem_rd == exe_rs` and `mem_rd_we` and `!mem_mem_read` |
| **F2** | MEM→EXE | `wb_data` from MEM stage output | 2-instruction gap, or load followed by ALU after 1 bubble | `wb_rd == exe_rs` and `wb_rd_we` |
| **F3** | WB→EXE | `wb_data` being written to regfile this cycle | 3-instruction gap | `wb2_rd == exe_rs` and `wb2_rd_we` |
| **F4** | WB→ID | Write-first register file | 3-instruction gap (alternative to F3) | Handled internally by register file |
| **F5** | MEM→MEM | `wb_data` from WB forwarded to MEM store data | Load-store forwarding (see §5.4) | `wb_rd == mem_store_rs` and `wb_rd_we` and `mem_mem_write` |

**Note on naming**: In the table above, the stages named in the path refer to where the data **comes from** and where it **goes to**. "EXE→EXE" means the data produced by the instruction that was in EXE last cycle (now the data sits in the EXE→MEM pipeline register, i.e., the MEM stage's input) is forwarded back to the current EXE stage's input mux.

**Priority** (when multiple paths match the same register):
1. F1 (youngest result — instruction just left EXE) — highest priority.
2. F2 (from MEM).
3. F3/F4 (from WB) — lowest priority.

If `rd == 0`, no forwarding occurs (r0 is always zero).

### 5.4 Load-Use Stall

**Problem**: a load instruction's result is not available until the end of MEM. When the load is in EXE, only the memory *address* has been computed — the actual loaded *value* hasn't arrived yet. If the next instruction (in ID) needs that register, no forwarding path can supply it.

**Detection** (in ID):
```
load_use_hazard = exe_mem_read
               && (exe_rd != 0)
               && (exe_rd == id_rs1 || exe_rd == id_rs2)
```

**Action**: insert a **1-cycle bubble**.
- IF1, IF2: freeze (hold current PC / instruction).
- ID: freeze (re-decode same instruction next cycle).
- EXE: receives a bubble/NOP.
- MEM, WB: continue normally.

After the 1 stall cycle, the load instruction moves to MEM, its data becomes available, and **F1** (EXE→EXE, which is now MEM's output → EXE mux) provides the value. No further stall needed.

**Compiler optimization**: schedule an independent instruction between a load and its consumer to avoid the stall entirely. This is the classic "load delay slot" optimization (but it's a software optimization, not an architectural load delay slot).

### 5.5 Store Data Forwarding (F5 — MEM→MEM)

**Scenario**:
```asm
LW   r1, 0(r2)      ; load r1 — result available at end of MEM
SW   r1, 4(r3)       ; store r1 — needs r1 as store data in MEM
```

Without F5: the `SW` needs `r1` in EXE to pass it to MEM as store data. But `r1` isn't ready until the `LW` finishes MEM. This causes a load-use stall.

With F5: the store data mux in MEM can grab the value directly from WB's output (the `LW` result, which by the time `SW` reaches MEM, is being written back in WB). This eliminates 1 stall cycle for the load→store pattern.

**Implementation**: a forwarding mux on `store_data` in the MEM stage, with WB's `wb_data` as an alternative source.

### 5.6 WAW and WAR Hazards

- **WAW** (Write After Write): not a concern in an in-order pipeline — instructions reach WB in program order.
- **WAR** (Write After Read): not a concern — ID reads happen before WB writes in the pipeline (or simultaneously with write-first semantics).

### 5.7 Forwarding Summary

**Complete forwarding network** at a glance:

| Consumer | Source: EXE→MEM reg | Source: MEM→WB reg | Source: WB output |
|---|---|---|---|
| **EXE ALU input (rs1)** | F1 (highest priority) | F2 | F3 |
| **EXE ALU input (rs2)** | F1 (highest priority) | F2 | F3 |
| **MEM store data** | — | — | F5 |
| **ID register read** | — | — | F4 (write-first regfile) |

Total forwarding muxes: **5** (2 for rs1 in EXE, 2 for rs2 in EXE, 1 for store data in MEM — each is a 3-or-4-input mux with priority encoding).

## 6) Pipeline Control

### 6.1 Stall Signal

A stall freezes stages IF1 through the stalling stage and inserts a bubble into the stage after the stall source.

Stall sources:
1. **Load-use dependency** (detected in ID): stalls IF1, IF2, ID. Bubble into EXE.
2. **D-Bus wait** (MEM waiting for slow ack): stalls IF1, IF2, ID, EXE. Bubble into WB. The entire pipeline freezes.
3. **Multiply latency** (if multi-cycle): stalls IF1, IF2, ID. Bubble into EXE, while EXE holds until multiply is done.
4. **Halt retirement** (detected in WB): hold PC and all pipeline registers.

### 6.2 Flush Signal

A flush replaces pipeline register contents with bubbles (effectively converting in-flight instructions to NOPs).

Flush sources:
1. **Branch mispredict** (detected in EXE): flush IF2→ID and ID→EXE pipeline registers. IF1 receives redirect target.
2. **Exception** (future v1): flush everything after the faulting instruction.

### 6.3 Priority

When both stall and flush are active in the same cycle:
- Stages **after** the stall point that are being flushed: flush wins (the instructions are being thrown away anyway).
- Stages **at or before** the stall point: stall wins (hold the valid instruction).

In practice, the common case is: a branch in EXE detects mispredict → flush IF2 and ID. If a load-use stall is also happening in ID, the stall is moot because ID is about to be flushed anyway.

### 6.4 Bubble Encoding

A bubble (invalid instruction) is represented in the pipeline register by clearing the `rd_we` and `mem_write` bits. This ensures it doesn't side-effect the register file or memory. No separate "valid" bit is strictly required, but one may be added for clarity and performance counter accuracy.

## 7) Multiply Handling

### 7.1 v0 Strategy

Target: single-cycle multiply using ECP5 DSP blocks (MULT18x18D primitive, pipelined mode).

- `MUL` (low 32 bits): 1 DSP block, result in 1 cycle if using the DSP's internal pipeline register.
- `MULH`/`MULHU`/`MULHSU` (high 32 bits): requires full 32×32→64 multiply, which typically needs 4 DSP blocks and a small adder tree. May be 1 or 2 cycles depending on timing.

### 7.2 Multi-Cycle Fallback

If the multiplier cannot complete in 1 cycle:
- EXE stage asserts `mul_busy`.
- Pipeline stalls until `mul_done`.
- Same stall mechanics as a D-Bus wait — freeze everything upstream.

### 7.3 Placement

Multiply is computed in **EXE**. The DSP block output feeds into the EXE→MEM pipeline register alongside regular ALU results. A mux selects between `alu_result` and `mul_result`.

## 8) Pipeline Timing Budget

For high frequency on ECP5 (target: 50+ MHz, stretch goal: 80+ MHz):

| Stage | Critical path concern |
|---|---|
| IF1 | PC mux (3 sources: sequential, predicted, redirect) → I-Bus address |
| IF2 | BRAM output → latch (minimal logic, just wires) |
| ID | Decode + register file read + hazard detection + forwarding select |
| EXE | Forwarding mux + ALU (32-bit add/sub or shift) + branch compare + result mux |
| MEM | D-Bus handshake + store data forwarding mux → data extraction (byte/half alignment) |
| WB | Register file write (simple, short path) |

The tightest stages are likely **ID** (decode + hazard detect) and **EXE** (forwarding mux + ALU + branch). If these become the bottleneck, the expansion to more stages (see §9) splits them.

## 9) Future Expansion Direction (11 Stages)

The 6-stage design is the starting point. For higher frequency, stages can be split:

| 6-stage | 11-stage expansion | Rationale |
|---|---|---|
| IF1 | IF1, IF2 | Separate PC generation from branch prediction lookup |
| IF2 | IF3 | BRAM output latch (unchanged) |
| ID | ID1, ID2 | Split early decode from register read + forwarding select |
| EXE | EXE1, EXE2 | Split forwarding mux + ALU compute from result select + branch compare |
| MEM | MEM1, MEM2 | Split address drive from data capture (helps SDRAM timing) |
| WB | WB1, WB2 | Split result mux from register file write |

**Tradeoffs of deeper pipeline**:
- **Higher frequency**: shorter combinational paths per stage → higher clock rate.
- **Higher branch penalty**: mispredict cost grows from 3 cycles to 5+ cycles.
- **More forwarding paths**: more stages means more bypass muxes and more complex priority logic.
- **More pipeline registers**: transistor area and routing cost.
- **Design complexity**: more control signals, harder to verify.

The expansion is mechanical — each split takes one stage and adds a pipeline register in the middle. No ISA changes are needed, only microarchitectural.

## 10) Performance Counters (Future)

For measuring pipeline efficiency, the following counters should be implemented:

| Counter | What it measures |
|---|---|
| `cycles` | Total clock cycles |
| `instrs_retired` | Instructions that reached WB (not flushed/bubble) |
| `branches` | Total branch instructions retired |
| `branch_mispredicts` | Mispredicted branches |
| `branch_taken` | Taken branches (for prediction accuracy analysis) |
| `loads` | Load instructions retired |
| `stores` | Store instructions retired |
| `load_use_stalls` | Cycles stalled due to load-use dependency |
| `dbus_stall_cycles` | Cycles stalled waiting for D-Bus ack |
| `mul_stall_cycles` | Cycles stalled waiting for multiply (if multi-cycle) |
| `bubbles` | Total bubble cycles (flushed instructions + stall bubbles) |

IPC = `instrs_retired / cycles`. Target for typical code: 0.7–0.9 IPC (limited by branches, load-use stalls, and bubbles).
