# NeoCoreFX Documentation Hub

This is the central entry point for project documentation.

## Start Here

- Project overview and quick commands: [README.md](README.md)
- Run and interpret verification: [TESTING_AND_VERIFICATION.md](TESTING_AND_VERIFICATION.md)
- Integrated simulation workflow: [docs/simulation-workflow.md](docs/simulation-workflow.md)
- Module-level RTL map: [MODULE_REFERENCE/README.md](MODULE_REFERENCE/README.md)

## Reading Paths

### Bring-Up Path

1. [README.md](README.md)
2. [TESTING_AND_VERIFICATION.md](TESTING_AND_VERIFICATION.md)
3. [tb/README.md](tb/README.md)
4. [mem/README.md](mem/README.md)

### RTL Deep-Dive Path

1. [MODULE_REFERENCE/README.md](MODULE_REFERENCE/README.md)
2. [docs/microarchitecture.md](docs/microarchitecture.md)
3. [docs/isa-v0.md](docs/isa-v0.md)
4. [docs/bus-architecture.md](docs/bus-architecture.md)

### ISA and Toolchain Path

1. [docs/isa-v0.md](docs/isa-v0.md)
2. [docs/pseudoinstructions.md](docs/pseudoinstructions.md)
3. [docs/pc-relative.md](docs/pc-relative.md)
4. [docs/relocations.md](docs/relocations.md)
5. [docs/far-branching.md](docs/far-branching.md)

## Documentation Map

### Project-Level Docs

- [README.md](README.md): repository overview, quick commands, and build entry points.
- [TESTING_AND_VERIFICATION.md](TESTING_AND_VERIFICATION.md): verification strategy, target matrix, and failure triage.

### Working Docs (`docs/`)

- [docs/simulation-workflow.md](docs/simulation-workflow.md): practical integrated-core runbook.
- [docs/microarchitecture.md](docs/microarchitecture.md): stage-level behavior notes.
- [docs/isa-v0.md](docs/isa-v0.md): ISA contract for v0.
- [docs/pseudoinstructions.md](docs/pseudoinstructions.md): pseudo-op mapping.
- [docs/pc-relative.md](docs/pc-relative.md): PC-relative semantics.
- [docs/relocations.md](docs/relocations.md): relocation behavior and assumptions.
- [docs/far-branching.md](docs/far-branching.md): long-range branch strategy.
- [docs/bus-architecture.md](docs/bus-architecture.md): BIU/memory bus integration notes.
- [docs/uart_mmio.h](docs/uart_mmio.h): UART MMIO register definitions and polling helpers.
- [docs/debug-interface.md](docs/debug-interface.md): optional hardware debug architecture, MMIO map, and UART protocol.
- [docs/debug_mmio.h](docs/debug_mmio.h): C definitions for debug MMIO register access.
- [docs/exceptions-future.md](docs/exceptions-future.md): planned exception model.

### Directory Guides

- [MODULE_REFERENCE/README.md](MODULE_REFERENCE/README.md): module index for RTL hierarchy.
- [tb/README.md](tb/README.md): testbench map and command guide.
- [mem/README.md](mem/README.md): program image catalog and hex format.

## Command Reference (Authoritative)

Run commands from repository root:

```bash
make run_smoke
make run_forward_hazard
make run_frontend_timing
make run_any PROGRAM=mem/test_smoke.hex
make run_any PROGRAM=mem/test_forwarding_hazard.hex
make profile_any PROGRAM=mem/test_smoke.hex
make waves_any PROGRAM=mem/test_smoke.hex
```

## Documentation Conventions

- Paths are repository-relative unless explicitly noted.
- Command examples assume `bash`/`zsh`.
- If docs disagree, trust this order:
  1. RTL (`rtl/*.sv`)
  2. `Makefile`
  3. Testbenches (`tb/*.sv`)
  4. Markdown docs
