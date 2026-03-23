# NeoCoreFX RTL

NeoCoreFX RTL, testbenches, and build tooling.

## Documentation

- Docs hub: [DOCS_INDEX.md](DOCS_INDEX.md)
- Verification guide: [TESTING_AND_VERIFICATION.md](TESTING_AND_VERIFICATION.md)
- Simulation runbook: [docs/simulation-workflow.md](docs/simulation-workflow.md)

## License

NeoCore-FX RTL and testbench code are licensed under Apache License 2.0.  
The NeoCore-FX / NeoCore16x32 toolchain is licensed separately under GPL-3.0.

## Directory Layout

```text
.
├── Makefile
├── MODULE_REFERENCE/
├── docs/
├── filelists/
│   ├── sim.f
│   ├── sim_core.f
│   ├── sim_core_smoke.f
│   ├── sim_core_any.f
│   ├── sim_forwarding_hazard.f
│   ├── sim_frontend_timing.f
│   ├── sim_biu.f
│   ├── sim_mem.f
│   ├── sim_halt.f
│   ├── sim_pipe.f
│   └── fpga.f
├── mem/
│   ├── *.hex (test_smoke.hex, test_halt.hex, coremark.hex, etc.)
│   └── README.md
├── rtl/
│   ├── core_pkg.sv
│   ├── mem_pkg.sv
│   ├── regfile.sv
│   ├── if1_stage.sv
│   ├── if2_stage.sv
│   ├── id_stage.sv
│   ├── exe_stage.sv
│   ├── mem_stage.sv
│   ├── wb_stage.sv
│   ├── biu.sv
│   ├── mem.sv
│   ├── neocorefx_core.sv
│   ├── neocorefx_top.sv
│   └── neocorefx_fpga_top.sv
├── tb/
│   ├── tb_pkg.sv
│   ├── tb_core_smoke.sv
│   ├── tb_core_any.sv
│   ├── tb_forwarding_hazard.sv
│   ├── tb_frontend_timing.sv
│   ├── tb_biu.sv
│   ├── tb_mem.sv
│   ├── tb_halt_path.sv
│   └── README.md
├── scripts/
│   ├── sim.py
│   ├── run_any.py
│   ├── bin2hex.py
│   └── wordhex_to_bytehex.py
└── ulx3s-85f-min.lpf
```

## Simulation

Default simulation target is the integrated core smoke testbench (`tb_core_smoke`) via `filelists/sim.f`.

```bash
make run
make waves
make list
```

Integrated core workflows:

```bash
make run_smoke
make run_forward_hazard
make run_frontend_timing
make run_any PROGRAM=mem/test_smoke.hex
make run_any PROGRAM=mem/test_forwarding_hazard.hex
make profile_any PROGRAM=mem/test_smoke.hex
make debug_any PROGRAM=mem/test_smoke.hex
make waves_any PROGRAM=mem/test_smoke.hex
make run_any PROGRAM=mem/coremark.hex VVP_ARGS=+UART_STDOUT
```

## UART MMIO (Phase 2)

Implemented D-Bus MMIO decode includes UART at `0x4000_0000`.

- `0x4000_0000` `TXDATA` (W): write byte to TX FIFO.
- `0x4000_0004` `RXDATA` (R/W): read received byte, or inject RX byte in simulation.
- `0x4000_0008` `STATUS` (R/W1C): bit0 `TX_READY`, bit1 `RX_VALID`, bit2 `TX_OVERRUN`, bit3 `RX_OVERRUN`.
- `0x4000_000C` `CTRL` (R/W): bit0 `TX_EN`, bit1 `RX_EN`.
- `0x4000_0010` `BAUDDIV` (R/W): UART bit-period divider.
- `TXDATA` applies backpressure: if TX FIFO is full, the write is stalled until space is available (no byte drop).
- Reset `BAUDDIV` defaults: synth/hardware `217` (25 MHz / 115200), simulation `8` for faster log throughput.

For simulation logging, pass `+UART_STDOUT` (via `VVP_ARGS`) to mirror transmitted bytes to console.

One-command generic loader helper:

```bash
python3 scripts/run_any.py --program mem/test_smoke.hex --profile
```

Run the memory-only testbench:

```bash
python3 scripts/sim.py build \
  --filelist filelists/sim_mem.f \
  --out build/sim_mem/tb_mem_simv \
  --top tb_mem \
  --build-dir build/sim_mem

python3 scripts/sim.py run --sim build/sim_mem/tb_mem_simv
```

Run the halt-path pipeline testbench (`B .` -> `halted`):

```bash
python3 scripts/sim.py build \
  --filelist filelists/sim_halt.f \
  --out build/sim_halt/tb_halt_path_simv \
  --top tb_halt_path \
  --build-dir build/sim_halt

python3 scripts/sim.py run --sim build/sim_halt/tb_halt_path_simv
```

Program format conversion helpers:

```bash
python3 scripts/bin2hex.py input.bin mem/input.hex
python3 scripts/wordhex_to_bytehex.py input_words.hex mem/input.hex
```

## FPGA Build (ULX3S 85F)

```bash
make fpga
make fpga-list
```
