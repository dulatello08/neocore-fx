# neocorefx_top.sv - Minimal Top Wrapper

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`neocorefx_top` wraps `counter` and exposes a compact clock/reset/enable interface.

## Module: `neocorefx_top`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `rst_n` | input | 1 | Active-low reset |
| `en` | input | 1 | Counter enable |
| `count` | output | 8 | Counter value |

## Internal Instances

- `counter` (WIDTH=8)
