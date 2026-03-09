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
│   ├── sim_biu.f
│   ├── sim_mem.f
│   ├── sim_halt.f
│   ├── sim_pipe.f
│   └── fpga.f
├── mem/
│   ├── test_smoke.hex
│   ├── test_halt.hex
│   ├── test_forwarding_hazard.hex
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
make run_any PROGRAM=mem/test_smoke.hex
make run_any PROGRAM=mem/test_forwarding_hazard.hex
make profile_any PROGRAM=mem/test_smoke.hex
make debug_any PROGRAM=mem/test_smoke.hex
make waves_any PROGRAM=mem/test_smoke.hex
```

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
