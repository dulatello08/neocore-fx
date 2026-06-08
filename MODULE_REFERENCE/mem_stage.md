# mem_stage.sv - MEM Stage

> [!TIP]
> Module Index: [README.md](README.md)

## Overview

`mem_stage` manages BIU D-port transactions for loads/stores, supports pending transaction tracking, and writes MEM->WB pipeline outputs.

## Module: `mem_stage`

### Key Interfaces

- EXE input bundle (`exe_*` controls/data).
- D-port request outputs (`d_req_o`, `d_we_o`, `d_size_o`, `d_addr_o`, `d_wdata_o`).
- D-port response inputs (`d_done_i`, `d_rdata_i`, `d_err_i`).
- MEM->WB output bundle (`memwb_*`).
- Halt propagation: `exe_is_halt_i` to `memwb_is_halt_o`.

### Main Behaviors

- Starts a transaction when EXE issues memory op and no pending op exists.
- Holds `pending_q` state while waiting for BIU completion.
- Extracts byte/half/word load data with optional sign extension.
- Asserts `stall_req_o` while transaction is active and incomplete.
- Passes halt metadata through non-memory and memory paths.

## Notes

Store-data forwarding from WB is applied before transaction launch.
