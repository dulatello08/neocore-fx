# NeoCoreFX RTL

NeoCoreFX RTL, testbenches, and build tooling.

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
│   ├── sim_biu.f
│   ├── sim_mem.f
│   ├── sim_pipe.f
│   └── fpga.f
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
│   ├── counter.sv
│   ├── neocorefx_top.sv
│   └── neocorefx_fpga_top.sv
├── tb/
│   ├── tb_pkg.sv
│   ├── tb_biu.sv
│   └── tb_mem.sv
├── scripts/
│   └── sim.py
└── ulx3s-85f-min.lpf
```

## Simulation

Default simulation target is `tb_biu` via `filelists/sim.f`.

```bash
make run
make waves
make list
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

## FPGA Build (ULX3S 85F)

```bash
make fpga
make fpga-list
```
