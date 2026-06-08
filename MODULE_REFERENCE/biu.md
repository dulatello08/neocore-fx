# biu.sv - Bus Interface Unit

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`biu` bridges CPU instruction/data request signals to bus-level `ibus_*` and `dbus_*` transactions.

## Module: `biu`

### Interfaces

- CPU instruction interface: `i_req`, `i_addr`, `i_busy`, `i_done`, `i_rdata`, `i_err`.
- CPU data interface: `d_req`, `d_we`, `d_size`, `d_addr`, `d_wdata`, `d_busy`, `d_done`, `d_rdata`, `d_err`.
- Bus interfaces: `ibus_*` and `dbus_*`.

### Main Behaviors

- Validates alignment and size constraints before issuing bus transactions.
- Generates byte/half/word lane select (`dbus_sel`) and shifted write data.
- Returns extracted read data for sub-word loads on D path.

## Notes

The block is combinational around request/response mapping, with `clk/rst` kept for interface consistency.
