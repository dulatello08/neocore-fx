# mem_pkg.sv - Memory Constants and Helpers

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`mem_pkg` defines global memory size/address constants and helper functions for address checks and byte-lane writes.

## Constants

| Name | Value | Description |
|------|-------|-------------|
| `MEM_BYTES` | `64 * 1024` | Total memory size in bytes |
| `MEM_WORD_BYTES` | `4` | Bytes per 32-bit word |
| `MEM_WORDS` | `MEM_BYTES / MEM_WORD_BYTES` | Total word entries |
| `MEM_BASE_ADDR` | `0x0000_0000` | First valid byte address |
| `MEM_LAST_ADDR` | `MEM_BASE_ADDR + MEM_BYTES - 1` | Last valid byte address |

## Helper Functions

- `mem_addr_in_range(addr)`: true when address is inside mapped memory.
- `mem_word_index(addr)`: converts byte address to word index (`addr[15:2]`).
- `mem_apply_write_sel(old_word, new_word, sel)`: merges selected byte lanes.

## Related Modules

- [mem.md](mem.md)
