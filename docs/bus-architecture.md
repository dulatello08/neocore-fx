# NeoCoreFX Bus Architecture

Status: v0.5 companion document — design direction for memory system evolution
Parent: [isa-v0.md](isa-v0.md)

## 1) Overview

NeoCoreFX uses a modified Harvard memory model: two independent buses (I-Bus for instruction fetch, D-Bus for load/store) accessing a unified 32-bit address space. This document describes the bus protocol, address map, and phased evolution from BRAM-only to a full memory system.

## 2) NeoCoreFX Bus Protocol ("NCX Bus")

A simple synchronous bus protocol inspired by Wishbone but simplified for this project.

### 2.1 Signal Table

**Master → Slave:**

| Signal   | Width | Description |
|----------|-------|-------------|
| `cyc`    | 1     | Bus cycle active. Held high for the entire transaction. |
| `stb`    | 1     | Strobe. High when this specific transfer is valid. |
| `we`     | 1     | Write enable. `1` = write, `0` = read. |
| `addr`   | 32    | Byte address. |
| `wdata`  | 32    | Write data (valid when `we=1`). |
| `sel`    | 4     | Byte lane select. Each bit enables one byte of the 32-bit data word. |

**Slave → Master:**

| Signal   | Width | Description |
|----------|-------|-------------|
| `ack`    | 1     | Acknowledge. Slave pulses this high for one cycle when the transaction completes. |
| `rdata`  | 32    | Read data (valid on the cycle `ack` is high, when `we=0`). |
| `err`    | 1     | Error. Slave pulses this instead of `ack` to signal a fault (unmapped, misaligned, etc.). Optional in v0. |

### 2.2 Byte Select (`sel`) Encoding

NeoCoreFX is **big-endian**. The byte select bits map to byte lanes as follows:

| `sel` bit | Byte lane | Address offset |
|-----------|-----------|----------------|
| `sel[3]`  | MSB       | `addr + 0`     |
| `sel[2]`  |           | `addr + 1`     |
| `sel[1]`  |           | `addr + 2`     |
| `sel[0]`  | LSB       | `addr + 3`     |

Examples (word-aligned base address):

| Operation                | `sel`    | Active bytes |
|--------------------------|----------|--------------|
| `LW` / `SW` (32-bit)    | `4'b1111`| all 4        |
| `LH` / `SH` at offset 0 | `4'b1100`| bytes 0–1    |
| `LH` / `SH` at offset 2 | `4'b0011`| bytes 2–3    |
| `LB` / `SB` at offset 0 | `4'b1000`| byte 0 only  |
| `LB` / `SB` at offset 1 | `4'b0100`| byte 1 only  |
| `LB` / `SB` at offset 2 | `4'b0010`| byte 2 only  |
| `LB` / `SB` at offset 3 | `4'b0001`| byte 3 only  |

### 2.3 Handshake Timing

#### Single-Cycle Read (BRAM)

```
           ┌───┐   ┌───┐   ┌───┐   ┌───┐
clk        │   │   │   │   │   │   │   │
       ────┘   └───┘   └───┘   └───┘   └───
cyc    ────────────────────────┐
       ________________________│____________
stb    ────────────┐           │
       ____________│___________│____________
we     ____________│___________________________
       ____________│___________________________
addr   ====ADDR====│___________________________
                   │           │
ack              __│___────────│____________
       _________/  │   \______│____________
rdata            ==│=DATA=====│____________
```

Timeline:
1. **Cycle 0**: Master asserts `cyc`, `stb`, `we=0`, `addr`. Transaction begins.
2. **Cycle 1**: Slave reads BRAM, asserts `ack=1` and drives `rdata`. Master captures data.
3. **Cycle 2**: Master deasserts `stb`. Transaction complete.

BRAM responds in **1 cycle** (combinational read from registered address, or registered output depending on BRAM configuration).

#### Multi-Cycle Read (SDRAM)

Same protocol, but `ack` comes later because SDRAM is slow:

1. **Cycle 0**: Master asserts `cyc`, `stb`, `we=0`, `addr`.
2. **Cycles 1–N**: Slave works on the SDRAM transfer. `ack` stays low. Master **stalls** (holds `stb` high, waits).
3. **Cycle N+1**: Slave asserts `ack=1`, drives `rdata`.
4. **Cycle N+2**: Master deasserts `stb`. Done.

The CPU pipeline stalls while waiting for `ack`. This is the price of accessing slow memory.

#### Write

Same as read, except `we=1` and `wdata` is driven by the master. The slave asserts `ack` when the write is committed.

### 2.4 Rules

1. `stb` must not be asserted without `cyc`.
2. `ack` must be exactly one cycle wide (pulse, not level).
3. Slave must not assert both `ack` and `err` in the same cycle.
4. `rdata` is only valid on the cycle `ack` is high and `we` is low.
5. `wdata` and `sel` must be stable from `stb` assertion until `ack`.
6. If no slave responds (no `ack` or `err` within a timeout), the bus controller may assert `err` on behalf of the missing slave. Timeout is implementation-defined.

## 3) Address Map

### 3.1 Phase 1 (BRAM Only)

```
0x0000_0000 ┌──────────────────────┐
            │      BRAM            │  64 KB (or less, depends on FPGA)
            │  (code + data)       │  Dual-port: I-Bus on port A, D-Bus on port B
0x0000_FFFF └──────────────────────┘
0x0001_0000 ┌──────────────────────┐
            │      unmapped        │  Access → bus error / undefined
0xFFFF_FFFF └──────────────────────┘
```

In this phase, there's no actual bus — the CPU connects directly to BRAM ports. The "bus" is just wires.

### 3.2 Phase 2 (BRAM + MMIO)

```
0x0000_0000 ┌──────────────────────┐
            │      BRAM            │  64 KB
0x0000_FFFF └──────────────────────┘
            │      unmapped        │
0x4000_0000 ┌──────────────────────┐
            │  MMIO region         │
            │  0x4000_0000  UART   │  256 B
            │  0x4000_0100  Timer  │  256 B
            │  0x4000_0200  GPIO   │  256 B
0x4000_0FFF └──────────────────────┘
            │      unmapped        │
```

Now you need a D-Bus decoder. I-Bus still goes straight to BRAM (you only execute from BRAM).

### 3.3 Phase 3 (BRAM + SDRAM + MMIO + Flash)

```
0x0000_0000 ┌──────────────────────┐
            │  BRAM (boot/fast)    │  64 KB
0x0000_FFFF └──────────────────────┘
            │      unmapped        │
0x2000_0000 ┌──────────────────────┐
            │      SDRAM           │  32 MB
0x21FF_FFFF └──────────────────────┘
            │      unmapped        │
0x4000_0000 ┌──────────────────────┐
            │  MMIO region         │  4 KB
0x4000_0FFF └──────────────────────┘
            │      unmapped        │
0x8000_0000 ┌──────────────────────┐
            │  Flash (read-only)   │  16 MB
0x80FF_FFFF └──────────────────────┘
```

## 4) Address Decoder

The decoder looks at the top bits of the address and routes the transaction to the correct slave. It's purely combinational:

```systemverilog
// D-Bus address decoder (simplified)
always_comb begin
    sel_bram  = 1'b0;
    sel_sdram = 1'b0;
    sel_mmio  = 1'b0;
    sel_flash = 1'b0;
    bus_err   = 1'b0;

    casez (dbus_addr[31:24])
        8'b0000_0000: sel_bram  = 1'b1;  // 0x00xx_xxxx
        8'b001?_????: sel_sdram = 1'b1;  // 0x20xx_xxxx .. 0x3Fxx_xxxx
        8'b0100_0000: sel_mmio  = 1'b1;  // 0x40xx_xxxx
        8'b1000_0000: sel_flash = 1'b1;  // 0x80xx_xxxx
        default:      bus_err   = 1'b1;  // unmapped
    endcase
end
```

The mux for read data:
```systemverilog
always_comb begin
    dbus_rdata = 32'h0;
    dbus_ack   = 1'b0;

    if (sel_bram)       begin dbus_rdata = bram_rdata;  dbus_ack = bram_ack;  end
    else if (sel_sdram) begin dbus_rdata = sdram_rdata; dbus_ack = sdram_ack; end
    else if (sel_mmio)  begin dbus_rdata = mmio_rdata;  dbus_ack = mmio_ack;  end
    else if (sel_flash) begin dbus_rdata = flash_rdata; dbus_ack = flash_ack; end
end
```

## 5) Topology

### 5.1 Phase 1 (Direct Wiring)

```
┌──────┐   I-Port    ┌──────────┐
│      ├────────────►│ BRAM     │
│ CPU  │   D-Port    │ (dual    │
│      ├────────────►│  port)   │
└──────┘             └──────────┘
```

No bus at all. I-Port and D-Port are just address/data/enable wires going straight into the BRAM's two ports.

### 5.2 Phase 2+ (Bus)

```
┌──────┐  I-Bus  ┌──────────┐        ┌──────────┐
│      ├────────►│ I-Decoder├───────►│ BRAM     │
│      │         └──────────┘  Port A │ (dual    │
│ CPU  │                              │  port)   │
│      │  D-Bus  ┌──────────┐  Port B │          │
│      ├────────►│ D-Decoder├───────►│          │
└──────┘         │          ├───────►│ SDRAM    │
                 │          ├───────►│ MMIO     │
                 │          ├───────►│ Flash    │
                 └──────────┘
```

- **I-Bus decoder**: simple, probably only routes to BRAM (or later an I-cache). Read-only.
- **D-Bus decoder**: full address decode, routes to all peripherals.
- Both decoders use the same NCX Bus protocol, same signals.

## 6) MMIO Devices

MMIO devices look like memory to the CPU but they're actually hardware registers. Example:

### 6.1 UART (Serial Port)

```
Offset  Register     Access   Description
0x00    TX_DATA      W        Write a byte to transmit
0x04    RX_DATA      R        Read received byte
0x08    STATUS       R        Bit 0: TX ready, Bit 1: RX valid
0x0C    CTRL         R/W      Bit 0: TX enable, Bit 1: RX enable
```

The CPU does `SW 1, 0x4000_0000(0)` to write to the UART TX register. The address decoder routes this to the UART module, which sees `addr=0x00` (lower bits), `we=1`, `wdata=<byte>`.

### 6.2 Timer

```
Offset  Register     Access   Description
0x00    COUNT        R        Current count value (32-bit)
0x04    COMPARE      R/W      Compare value (for interrupt/flag, future)
0x08    CTRL         R/W      Bit 0: enable, Bit 1: auto-reload
```

### 6.3 GPIO/LEDs

```
Offset  Register     Access   Description
0x00    OUT          R/W      Output register (directly drives LEDs/pins)
0x04    IN           R        Input register (reads buttons/pins)
0x08    DIR          R/W      Direction (0=input, 1=output) per bit
```

## 7) Evolution Strategy

| Phase | What you add | Complexity | What changes in RTL |
|-------|-------------|-----------|-------------------|
| **1** | BRAM only | Trivial | Direct port wiring, no bus |
| **1.5** | Soft UART (MMIO) | Low | Add D-Bus decoder (BRAM + UART), I-Bus stays direct |
| **2** | Timer + GPIO | Low | Extend D-Bus decoder with more MMIO slaves |
| **3** | SDRAM controller | Medium | SDRAM slave on D-Bus, multi-cycle ack, possible burst |
| **3.5** | Flash (SPI) | Medium | Flash slave on D-Bus, very slow (many cycles per ack) |
| **4** | Cache (I$, D$) | Hard | Insert cache between CPU and bus, tag/data arrays |

Each phase is additive — you never throw away the previous work, you just plug in more slaves to the decoder.

## 8) Stalling the CPU Pipeline

When the CPU does a load/store and the slave doesn't ack immediately, the pipeline must **stall**. This is the key interaction between the bus and the CPU:

1. CPU issues a D-Bus transaction (`stb=1`).
2. CPU watches `ack`.
3. If `ack` comes back in 1 cycle (BRAM): no stall, pipeline flows normally.
4. If `ack` takes N cycles (SDRAM): pipeline freezes for N-1 extra cycles. All pipeline registers hold their values. No new instruction is fetched.

The stall signal is simple:
```systemverilog
assign pipeline_stall = dbus_stb && !dbus_ack;
```

When `pipeline_stall` is high, every pipeline register keeps its current value, and the PC doesn't advance.

## 9) Why Not Use Wishbone Directly?

Wishbone is fine but:
1. It has features you don't need yet (burst modes, tag signals, multiple bus widths).
2. It has naming conventions that are confusing (the `_o`/`_i` suffix convention).
3. Building your own forces you to understand every signal, which matters when you're debugging waveforms at 2 AM.

The NCX Bus is essentially Wishbone B3 pipelined mode stripped down to the essentials. If you ever want to use a Wishbone-compatible IP core, wrapping NCX ↔ Wishbone is trivial (mostly just renaming wires).
