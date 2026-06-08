# counter.sv - Counter Primitive

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`counter` is a parameterized synchronous up-counter used by the wrapper tops.

## Module: `counter`

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WIDTH` | `8` | Counter bit width |

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `rst_n` | input | 1 | Active-low reset |
| `en` | input | 1 | Increment enable |
| `count` | output | `WIDTH` | Counter value |

## Notes

Counter increments by 1 each enabled clock cycle.
