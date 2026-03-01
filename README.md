# NeoCoreFX

WIP!!

## Directory Layout

```text
.
├── Makefile
├── docs/
├── filelists/
│   ├── sim.f
│   └── fpga.f
├── rtl/
│   ├── ncfx_counter.sv
│   ├── neocorefx_top.sv
│   └── neocorefx_fpga_top.sv
├── tb/
│   ├── tb_pkg.sv
│   ├── tb_clock_reset.sv
│   ├── test_smoke.sv
│   └── tb_neocorefx_top.sv
├── scripts/
│   └── sim.py
└── ulx3s-85f-min.lpf
```

## Simulation

```bash
make run
make waves
make list
```

## FPGA Build (ULX3S 85F)

```bash
make fpga
make fpga-list
```

