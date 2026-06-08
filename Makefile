PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
SV2V ?= sv2v
NEXTPNR ?= nextpnr-ecp5
ECPPACK ?= ecppack
ECPBRAM ?= ecpbram

SIM_HELPER := scripts/sim.py

BUILD_ROOT ?= build
SIM_BUILD_DIR ?= $(BUILD_ROOT)/sim
FPGA_BUILD_DIR ?= $(BUILD_ROOT)/fpga
WAVE_DIR ?= $(BUILD_ROOT)/waves

SIM_FILELIST ?= filelists/sim.f
SIM_TOP ?= tb_core_smoke
SIM_BIN ?= $(SIM_BUILD_DIR)/simv
IVERILOG_FLAGS ?= -g2012 -Wall -Winfloop
VVP_ARGS ?=

CORE_SMOKE_FILELIST ?= filelists/sim_core_smoke.f
CORE_SMOKE_TOP ?= tb_core_smoke
CORE_SMOKE_BUILD_DIR ?= $(BUILD_ROOT)/sim_core_smoke
CORE_SMOKE_BIN ?= $(CORE_SMOKE_BUILD_DIR)/tb_core_smoke_simv

CORE_ANY_FILELIST ?= filelists/sim_core_any.f
CORE_ANY_TOP ?= tb_core_any
CORE_ANY_BUILD_DIR ?= $(BUILD_ROOT)/sim_core_any
CORE_ANY_BIN ?= $(CORE_ANY_BUILD_DIR)/tb_core_any_simv

FWD_HAZ_FILELIST ?= filelists/sim_forwarding_hazard.f
FWD_HAZ_TOP ?= tb_forwarding_hazard
FWD_HAZ_BUILD_DIR ?= $(BUILD_ROOT)/sim_forwarding_hazard
FWD_HAZ_BIN ?= $(FWD_HAZ_BUILD_DIR)/tb_forwarding_hazard_simv

FRONTEND_TIMING_FILELIST ?= filelists/sim_frontend_timing.f
FRONTEND_TIMING_TOP ?= tb_frontend_timing
FRONTEND_TIMING_BUILD_DIR ?= $(BUILD_ROOT)/sim_frontend_timing
FRONTEND_TIMING_BIN ?= $(FRONTEND_TIMING_BUILD_DIR)/tb_frontend_timing_simv

DEBUG_MMIO_FILELIST ?= filelists/sim_debug_mmio.f
DEBUG_MMIO_TOP ?= tb_debug_mmio
DEBUG_MMIO_BUILD_DIR ?= $(BUILD_ROOT)/sim_debug_mmio
DEBUG_MMIO_BIN ?= $(DEBUG_MMIO_BUILD_DIR)/tb_debug_mmio_simv

DEBUG_UART_ROUTER_FILELIST ?= filelists/sim_debug_uart_claim.f
DEBUG_UART_ROUTER_TOP ?= tb_debug_uart_claim
DEBUG_UART_ROUTER_BUILD_DIR ?= $(BUILD_ROOT)/sim_debug_uart_router
DEBUG_UART_ROUTER_BIN ?= $(DEBUG_UART_ROUTER_BUILD_DIR)/tb_debug_uart_router_simv

MEM_FILELIST ?= filelists/sim_mem.f
MEM_TOP ?= tb_mem
MEM_BUILD_DIR ?= $(BUILD_ROOT)/sim_mem
MEM_BIN ?= $(MEM_BUILD_DIR)/tb_mem_simv
MEM_NODEBUG_FILELIST ?= filelists/sim_mem_nodebug.f
MEM_NODEBUG_TOP ?= tb_mem_nodebug
MEM_NODEBUG_BUILD_DIR ?= $(BUILD_ROOT)/sim_mem_nodebug
MEM_NODEBUG_BIN ?= $(MEM_NODEBUG_BUILD_DIR)/tb_mem_nodebug_simv
MEM_RANDOM_WORDHEX ?= $(MEM_BUILD_DIR)/mem_random.wordhex
MEM_RANDOM_BANK_PREFIX ?= $(MEM_BUILD_DIR)/mem_random

PROGRAM ?= mem/test_smoke.hex
BIN_INPUT ?=
WORDHEX_INPUT ?=
BYTEHEX_INPUT ?=
HEX_OUTPUT ?= mem/output.hex

FPGA_FILELIST ?= filelists/fpga.f
FPGA_TOP ?= neocorefx_fpga_top
LPF ?= ulx3s-85f-min.lpf
ECP5_SIZE ?= 85k
ECP5_PACKAGE ?= CABGA381
ECP5_SPEED ?= 6
ECP5_FREQ ?= 42
BITSTREAM ?= $(FPGA_BUILD_DIR)/$(FPGA_TOP).bit

FPGA_BRAM_WIDTH ?= 32
FPGA_BRAM_DEPTH ?= 16384
FPGA_RANDOM_BRAM ?= 0
FPGA_RANDOM_SEED ?=
NEXTPNR_SEED ?= 1
FPGA_BRAM_INIT_WORDHEX ?=
FPGA_BRAM_TO_WORDHEX ?=
FPGA_PROGRAM_WORDHEX ?= $(FPGA_BUILD_DIR)/program.wordhex
FPGA_PROGRAM_BYTEHEX ?= $(FPGA_BUILD_DIR)/program.bytehex
FPGA_PROGRAM_BANK_PREFIX ?= $(FPGA_BUILD_DIR)/program_bank32
FPGA_GARBAGE_WORDHEX ?= $(FPGA_BUILD_DIR)/garbage.wordhex
FPGA_GARBAGE_BANK_PREFIX ?= $(FPGA_BUILD_DIR)/bank32_garbage
FPGA_PATCHED_CONFIG ?= $(FPGA_BUILD_DIR)/core.config

CLR_RESET := \033[0m
CLR_BOLD := \033[1m
CLR_CYAN := \033[36m
CLR_BLUE := \033[34m
CLR_GREEN := \033[32m
CLR_YELLOW := \033[33m
CLR_MAGENTA := \033[35m

define banner
	@printf "$(CLR_BOLD)$(CLR_MAGENTA)\n========== %s ==========$(CLR_RESET)\n" "$(1)"
endef

define note
	@printf "$(CLR_CYAN)[neo]$(CLR_RESET) %s\n" "$(1)"
endef

FPGA_EXTRA_FLAGS := --ecpbram $(ECPBRAM) --bram-width $(FPGA_BRAM_WIDTH) --bram-depth $(FPGA_BRAM_DEPTH)
ifneq ($(FPGA_RANDOM_BRAM),0)
FPGA_EXTRA_FLAGS += --bram-random-init
endif
ifneq ($(strip $(FPGA_RANDOM_SEED)),)
FPGA_EXTRA_FLAGS += --bram-random-seed $(FPGA_RANDOM_SEED)
endif
ifneq ($(strip $(FPGA_BRAM_INIT_WORDHEX)),)
FPGA_EXTRA_FLAGS += --bram-init-wordhex $(FPGA_BRAM_INIT_WORDHEX)
endif
ifneq ($(strip $(FPGA_BRAM_TO_WORDHEX)),)
FPGA_EXTRA_FLAGS += --bram-to-wordhex $(FPGA_BRAM_TO_WORDHEX)
endif

FPGA_EXTRA_FLAGS += --seed $(NEXTPNR_SEED) --report $(FPGA_BUILD_DIR)/report_$(NEXTPNR_SEED).json

.PHONY: help check-sim check-fpga check-no-svh dirs build run waves list \
	core-smoke-build core-smoke-run core-any-build core-any-run \
	forward-hazard-build forward-hazard-run \
	mem-build mem-run mem-nodebug-build mem-nodebug-run run_mem run_mem_nodebug run_mem_random \
	frontend-timing-build frontend-timing-run \
	debug-mmio-build debug-mmio-run debug-uart-router-build debug-uart-router-run \
	run_smoke run_any run_forward_hazard run_frontend_timing run_debug_mmio run_debug_uart_router run_debug_uart_claim profile_any debug_any waves_any \
	smoke-hex bin2hex wordhex2byte bytehex2word \
	fpga fpga-program fpga-list clean clobber

help:
	@printf "$(CLR_BOLD)$(CLR_BLUE)NeoCoreFX Build Targets$(CLR_RESET)\n"
	@printf "  $(CLR_GREEN)make build$(CLR_RESET)      Compile simulation binary (iverilog)\n"
	@printf "  $(CLR_GREEN)make run$(CLR_RESET)        Build + run simulation (vvp)\n"
	@printf "  $(CLR_GREEN)make waves$(CLR_RESET)      Build + run with +WAVES (VCD)\n"
	@printf "  $(CLR_GREEN)make run_smoke$(CLR_RESET)  Build + run integrated core smoke TB\n"
	@printf "  $(CLR_GREEN)make run_any$(CLR_RESET)    Run generic TB with PROGRAM=<byte-hex>\n"
	@printf "  $(CLR_GREEN)make run_mem$(CLR_RESET)    Run memory+UART unit test TB\n"
	@printf "  $(CLR_GREEN)make run_mem_nodebug$(CLR_RESET) Run memory fabric with debug structurally removed\n"
	@printf "  $(CLR_GREEN)make run_mem_random$(CLR_RESET) Run memory TB with randomized BRAM init image\n"
	@printf "  $(CLR_GREEN)make run_forward_hazard$(CLR_RESET) Run forwarding-hazard regression TB\n"
	@printf "  $(CLR_GREEN)make run_frontend_timing$(CLR_RESET) Run frontend stall+redirect timing TB\n"
	@printf "  $(CLR_GREEN)make run_debug_mmio$(CLR_RESET) Run debug MMIO block testbench\n"
	@printf "  $(CLR_GREEN)make run_debug_uart_router$(CLR_RESET) Run ncdb UART router testbench\n"
	@printf "  $(CLR_GREEN)make profile_any$(CLR_RESET) Run generic TB with +PROFILE stats\n"
	@printf "  $(CLR_GREEN)make debug_any$(CLR_RESET)  Run generic TB with +DEBUG trace\n"
	@printf "  $(CLR_GREEN)make waves_any$(CLR_RESET)  Run generic TB with +WAVES dump\n"
	@printf "  $(CLR_GREEN)make smoke-hex$(CLR_RESET)  Regenerate mem/test_smoke.hex\n"
	@printf "  $(CLR_GREEN)make bin2hex$(CLR_RESET)    BIN_INPUT=<bin> HEX_OUTPUT=<hex>\n"
	@printf "  $(CLR_GREEN)make wordhex2byte$(CLR_RESET) WORDHEX_INPUT=<wordhex> HEX_OUTPUT=<hex>\n"
	@printf "  $(CLR_GREEN)make bytehex2word$(CLR_RESET) BYTEHEX_INPUT=<bytehex> HEX_OUTPUT=<wordhex>\n"
	@printf "  $(CLR_GREEN)make list$(CLR_RESET)       Show resolved simulation source order\n"
	@printf "  $(CLR_GREEN)make fpga$(CLR_RESET)       Build FPGA with random BRAM init (yosys/nextpnr/ecppack)\n"
	@printf "  $(CLR_GREEN)make fpga-program$(CLR_RESET) Patch BRAM with PROGRAM=<hex|bin> via ecpbram\n"
	@printf "  $(CLR_GREEN)make fpga-list$(CLR_RESET)  Show resolved FPGA source order\n"
	@printf "  $(CLR_GREEN)make clean$(CLR_RESET)      Remove simulation build directory\n"
	@printf "  $(CLR_GREEN)make clobber$(CLR_RESET)    Remove full build directory\n"
	@printf "\n$(CLR_BOLD)Key Variables$(CLR_RESET)\n"
	@printf "  SIM_TOP=$(SIM_TOP)\n"
	@printf "  SIM_FILELIST=$(SIM_FILELIST)\n"
	@printf "  PROGRAM=$(PROGRAM)\n"
	@printf "  BIN_INPUT=$(BIN_INPUT)\n"
	@printf "  WORDHEX_INPUT=$(WORDHEX_INPUT)\n"
	@printf "  HEX_OUTPUT=$(HEX_OUTPUT)\n"
	@printf "  FPGA_TOP=$(FPGA_TOP)\n"
	@printf "  FPGA_FILELIST=$(FPGA_FILELIST)\n"
	@printf "  LPF=$(LPF)\n"
	@printf "  ECP5_SIZE=$(ECP5_SIZE) ECP5_PACKAGE=$(ECP5_PACKAGE) ECP5_SPEED=$(ECP5_SPEED)\n"
	@printf "  SV2V=$(SV2V) YOSYS=$(YOSYS) NEXTPNR=$(NEXTPNR) ECPPACK=$(ECPPACK) ECPBRAM=$(ECPBRAM)\n"

check-sim:
	@command -v $(PYTHON) >/dev/null
	@command -v $(IVERILOG) >/dev/null
	@command -v $(VVP) >/dev/null
	@$(MAKE) --no-print-directory check-no-svh

check-no-svh:
	@if find rtl tb filelists -type f -name '*.svh' | grep -q .; then \
		echo "ERROR: .svh files are banned. Convert to .sv modules/files."; \
		find rtl tb filelists -type f -name '*.svh'; \
		exit 1; \
	fi

check-fpga:
	@command -v $(PYTHON) >/dev/null
	@command -v $(SV2V) >/dev/null
	@command -v $(YOSYS) >/dev/null
	@command -v $(NEXTPNR) >/dev/null
	@command -v $(ECPPACK) >/dev/null
	@command -v $(ECPBRAM) >/dev/null
	@$(MAKE) --no-print-directory check-no-svh

dirs:
	@mkdir -p $(SIM_BUILD_DIR) $(FPGA_BUILD_DIR) $(WAVE_DIR)

build: check-sim dirs
	$(call banner,SIM BUILD)
	$(call note,Top: $(SIM_TOP))
	@$(PYTHON) $(SIM_HELPER) build \
		--filelist $(SIM_FILELIST) \
		--out $(SIM_BIN) \
		--top $(SIM_TOP) \
		--iverilog $(IVERILOG) \
		--flags "$(IVERILOG_FLAGS)" \
		--build-dir $(SIM_BUILD_DIR)

run: build
	$(call banner,SIM RUN)
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(SIM_BIN) \
		--vvp $(VVP) \
		--vvp-args "$(VVP_ARGS)"

waves: build
	$(call banner,SIM WAVES)
	$(call note,Writing VCD to $(WAVE_DIR))
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(SIM_BIN) \
		--vvp $(VVP) \
		--vvp-args "$(VVP_ARGS)" \
		--plusarg WAVES

list: check-sim
	$(call banner,SIM SOURCE LIST)
	@$(PYTHON) $(SIM_HELPER) list \
		--filelist $(SIM_FILELIST)

core-smoke-build: check-sim
	$(call banner,CORE SMOKE BUILD)
	@mkdir -p $(CORE_SMOKE_BUILD_DIR)
	@$(PYTHON) $(SIM_HELPER) build \
		--filelist $(CORE_SMOKE_FILELIST) \
		--out $(CORE_SMOKE_BIN) \
		--top $(CORE_SMOKE_TOP) \
		--iverilog $(IVERILOG) \
		--flags "$(IVERILOG_FLAGS)" \
		--build-dir $(CORE_SMOKE_BUILD_DIR)

core-smoke-run: core-smoke-build
	$(call banner,CORE SMOKE RUN)
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(CORE_SMOKE_BIN) \
		--vvp $(VVP) \
		--vvp-args "$(VVP_ARGS)"

run_smoke: core-smoke-run

core-any-build: check-sim
	$(call banner,CORE ANY BUILD)
	@mkdir -p $(CORE_ANY_BUILD_DIR)
	@$(PYTHON) $(SIM_HELPER) build \
		--filelist $(CORE_ANY_FILELIST) \
		--out $(CORE_ANY_BIN) \
		--top $(CORE_ANY_TOP) \
		--iverilog $(IVERILOG) \
		--flags "$(IVERILOG_FLAGS)" \
		--build-dir $(CORE_ANY_BUILD_DIR)

core-any-run: core-any-build
	$(call banner,CORE ANY RUN)
	@if [ ! -f "$(PROGRAM)" ]; then \
		echo "ERROR: Program file '$(PROGRAM)' not found."; \
		exit 1; \
	fi
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(CORE_ANY_BIN) \
		--vvp $(VVP) \
		--vvp-args "+PROGRAM=$(PROGRAM) $(VVP_ARGS)"

run_any: core-any-run

mem-build: check-sim
	$(call banner,MEM TB BUILD)
	@mkdir -p $(MEM_BUILD_DIR)
	@$(PYTHON) $(SIM_HELPER) build \
		--filelist $(MEM_FILELIST) \
		--out $(MEM_BIN) \
		--top $(MEM_TOP) \
		--iverilog $(IVERILOG) \
		--flags "$(IVERILOG_FLAGS)" \
		--build-dir $(MEM_BUILD_DIR)

mem-run: mem-build
	$(call banner,MEM TB RUN)
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(MEM_BIN) \
		--vvp $(VVP) \
		--vvp-args "$(VVP_ARGS)"

run_mem: mem-run

mem-nodebug-build: check-sim
	$(call banner,MEM NODEBUG TB BUILD)
	@mkdir -p $(MEM_NODEBUG_BUILD_DIR)
	@$(PYTHON) $(SIM_HELPER) build \
		--filelist $(MEM_NODEBUG_FILELIST) \
		--out $(MEM_NODEBUG_BIN) \
		--top $(MEM_NODEBUG_TOP) \
		--iverilog $(IVERILOG) \
		--flags "$(IVERILOG_FLAGS)" \
		--build-dir $(MEM_NODEBUG_BUILD_DIR)

mem-nodebug-run: mem-nodebug-build
	$(call banner,MEM NODEBUG TB RUN)
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(MEM_NODEBUG_BIN) \
		--vvp $(VVP) \
		--vvp-args "$(VVP_ARGS)"

run_mem_nodebug: mem-nodebug-run

run_mem_random: check-sim check-fpga
	$(call banner,MEM TB RANDOM INIT)
	@mkdir -p $(MEM_BUILD_DIR)
	@$(ECPBRAM) -g "$(MEM_RANDOM_WORDHEX)" -w $(FPGA_BRAM_WIDTH) -d $(FPGA_BRAM_DEPTH) \
		$(if $(strip $(FPGA_RANDOM_SEED)),-s $(FPGA_RANDOM_SEED),)
	@$(PYTHON) scripts/wordhex_split_banks.py "$(MEM_RANDOM_WORDHEX)" "$(MEM_RANDOM_BANK_PREFIX)"
	@$(PYTHON) $(SIM_HELPER) build \
		--filelist $(MEM_FILELIST) \
		--out $(MEM_BIN) \
		--top $(MEM_TOP) \
		--iverilog $(IVERILOG) \
		--flags "$(IVERILOG_FLAGS) -DMEM_INIT_HEX_BANK0=\\\"$(abspath $(MEM_RANDOM_BANK_PREFIX).bank0.wordhex)\\\" -DMEM_INIT_HEX_BANK1=\\\"$(abspath $(MEM_RANDOM_BANK_PREFIX).bank1.wordhex)\\\" -DMEM_INIT_HEX_BANK2=\\\"$(abspath $(MEM_RANDOM_BANK_PREFIX).bank2.wordhex)\\\" -DMEM_INIT_HEX_BANK3=\\\"$(abspath $(MEM_RANDOM_BANK_PREFIX).bank3.wordhex)\\\"" \
		--build-dir $(MEM_BUILD_DIR)
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(MEM_BIN) \
		--vvp $(VVP) \
		--vvp-args "$(VVP_ARGS)"

forward-hazard-build: check-sim
	$(call banner,FORWARD HAZARD BUILD)
	@mkdir -p $(FWD_HAZ_BUILD_DIR)
	@$(PYTHON) $(SIM_HELPER) build \
		--filelist $(FWD_HAZ_FILELIST) \
		--out $(FWD_HAZ_BIN) \
		--top $(FWD_HAZ_TOP) \
		--iverilog $(IVERILOG) \
		--flags "$(IVERILOG_FLAGS)" \
		--build-dir $(FWD_HAZ_BUILD_DIR)

forward-hazard-run: forward-hazard-build
	$(call banner,FORWARD HAZARD RUN)
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(FWD_HAZ_BIN) \
		--vvp $(VVP) \
		--vvp-args "$(VVP_ARGS)"

run_forward_hazard: forward-hazard-run

frontend-timing-build: check-sim
	$(call banner,FRONTEND TIMING BUILD)
	@mkdir -p $(FRONTEND_TIMING_BUILD_DIR)
	@$(PYTHON) $(SIM_HELPER) build \
		--filelist $(FRONTEND_TIMING_FILELIST) \
		--out $(FRONTEND_TIMING_BIN) \
		--top $(FRONTEND_TIMING_TOP) \
		--iverilog $(IVERILOG) \
		--flags "$(IVERILOG_FLAGS)" \
		--build-dir $(FRONTEND_TIMING_BUILD_DIR)

frontend-timing-run: frontend-timing-build
	$(call banner,FRONTEND TIMING RUN)
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(FRONTEND_TIMING_BIN) \
		--vvp $(VVP) \
		--vvp-args "$(VVP_ARGS)"

run_frontend_timing: frontend-timing-run

debug-mmio-build: check-sim
	$(call banner,DEBUG MMIO BUILD)
	@mkdir -p $(DEBUG_MMIO_BUILD_DIR)
	@$(PYTHON) $(SIM_HELPER) build \
		--filelist $(DEBUG_MMIO_FILELIST) \
		--out $(DEBUG_MMIO_BIN) \
		--top $(DEBUG_MMIO_TOP) \
		--iverilog $(IVERILOG) \
		--flags "$(IVERILOG_FLAGS)" \
		--build-dir $(DEBUG_MMIO_BUILD_DIR)

debug-mmio-run: debug-mmio-build
	$(call banner,DEBUG MMIO RUN)
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(DEBUG_MMIO_BIN) \
		--vvp $(VVP) \
		--vvp-args "$(VVP_ARGS)"

run_debug_mmio: debug-mmio-run

debug-uart-router-build: check-sim
	$(call banner,DEBUG UART ROUTER BUILD)
	@mkdir -p $(DEBUG_UART_ROUTER_BUILD_DIR)
	@$(PYTHON) $(SIM_HELPER) build \
		--filelist $(DEBUG_UART_ROUTER_FILELIST) \
		--out $(DEBUG_UART_ROUTER_BIN) \
		--top $(DEBUG_UART_ROUTER_TOP) \
		--iverilog $(IVERILOG) \
		--flags "$(IVERILOG_FLAGS)" \
		--build-dir $(DEBUG_UART_ROUTER_BUILD_DIR)

debug-uart-router-run: debug-uart-router-build
	$(call banner,DEBUG UART ROUTER RUN)
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(DEBUG_UART_ROUTER_BIN) \
		--vvp $(VVP) \
		--vvp-args "$(VVP_ARGS)"

run_debug_uart_router: debug-uart-router-run

run_debug_uart_claim: debug-uart-router-run
	
profile_any: core-any-build
	$(call banner,CORE ANY PROFILE)
	@if [ ! -f "$(PROGRAM)" ]; then \
		echo "ERROR: Program file '$(PROGRAM)' not found."; \
		exit 1; \
	fi
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(CORE_ANY_BIN) \
		--vvp $(VVP) \
		--vvp-args "+PROGRAM=$(PROGRAM) +PROFILE $(VVP_ARGS)"

debug_any: core-any-build
	$(call banner,CORE ANY DEBUG)
	@if [ ! -f "$(PROGRAM)" ]; then \
		echo "ERROR: Program file '$(PROGRAM)' not found."; \
		exit 1; \
	fi
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(CORE_ANY_BIN) \
		--vvp $(VVP) \
		--vvp-args "+PROGRAM=$(PROGRAM) +DEBUG $(VVP_ARGS)"

waves_any: core-any-build
	$(call banner,CORE ANY WAVES)
	@if [ ! -f "$(PROGRAM)" ]; then \
		echo "ERROR: Program file '$(PROGRAM)' not found."; \
		exit 1; \
	fi
	@$(PYTHON) $(SIM_HELPER) run \
		--sim $(CORE_ANY_BIN) \
		--vvp $(VVP) \
		--vvp-args "+PROGRAM=$(PROGRAM) $(VVP_ARGS)" \
		--plusarg WAVES

smoke-hex:
	$(call banner,SMOKE HEX)
	@$(PYTHON) scripts/make_smoke_hex.py --out mem/test_smoke.hex

bin2hex:
	$(call banner,BINARY TO HEX)
	@if [ -z "$(BIN_INPUT)" ]; then \
		echo "ERROR: BIN_INPUT is required."; \
		echo "Usage: make bin2hex BIN_INPUT=input.bin HEX_OUTPUT=mem/output.hex"; \
		exit 1; \
	fi
	@$(PYTHON) scripts/bin2hex.py "$(BIN_INPUT)" "$(HEX_OUTPUT)"

wordhex2byte:
	$(call banner,WORDHEX TO BYTEHEX)
	@if [ -z "$(WORDHEX_INPUT)" ]; then \
		echo "ERROR: WORDHEX_INPUT is required."; \
		echo "Usage: make wordhex2byte WORDHEX_INPUT=input.wordhex HEX_OUTPUT=mem/output.hex"; \
		exit 1; \
	fi
	@$(PYTHON) scripts/wordhex_to_bytehex.py "$(WORDHEX_INPUT)" "$(HEX_OUTPUT)"

bytehex2word:
	$(call banner,BYTEHEX TO WORDHEX)
	@if [ -z "$(BYTEHEX_INPUT)" ]; then \
		echo "ERROR: BYTEHEX_INPUT is required."; \
		echo "Usage: make bytehex2word BYTEHEX_INPUT=input.bytehex HEX_OUTPUT=mem/output.wordhex"; \
		exit 1; \
	fi
	@$(PYTHON) scripts/bytehex_to_wordhex.py "$(BYTEHEX_INPUT)" "$(HEX_OUTPUT)" --depth $(FPGA_BRAM_DEPTH)

fpga: check-fpga dirs
	$(call banner,FPGA BUILD)
	$(call note,Top: $(FPGA_TOP))
	$(call note,Constraints: $(LPF))
	@$(PYTHON) -c 'import os, pathlib; d=int($(FPGA_BRAM_DEPTH)); p=pathlib.Path("$(FPGA_GARBAGE_WORDHEX)"); b=os.urandom(d*4); p.write_text("".join("{:08x}\n".format(int.from_bytes(b[i*4:(i+1)*4], "little")) for i in range(d)), encoding="utf-8")'
	@$(PYTHON) scripts/wordhex_split_banks.py "$(FPGA_GARBAGE_WORDHEX)" "$(FPGA_GARBAGE_BANK_PREFIX)"
	@$(PYTHON) $(SIM_HELPER) fpga \
		--filelist $(FPGA_FILELIST) \
		--top $(FPGA_TOP) \
		--lpf $(LPF) \
		--build-dir $(FPGA_BUILD_DIR) \
		--size $(ECP5_SIZE) \
		--package $(ECP5_PACKAGE) \
		--speed $(ECP5_SPEED) \
		--freq $(ECP5_FREQ) \
		--yosys $(YOSYS) \
		--sv2v $(SV2V) \
		--nextpnr $(NEXTPNR) \
		--ecppack $(ECPPACK) \
		$(FPGA_EXTRA_FLAGS) \
		--bram-init-wordhex $(abspath $(FPGA_GARBAGE_WORDHEX)) \
		--timing-allow-fail \
		--bit $(BITSTREAM)

fpga-program: check-fpga dirs
	$(call banner,FPGA PROGRAM)
	@if [ ! -f "$(PROGRAM)" ]; then \
		echo "ERROR: Program file '$(PROGRAM)' not found."; \
		exit 1; \
	fi
	@if [ ! -f "$(FPGA_BUILD_DIR)/$(FPGA_TOP).config" ]; then \
		echo "ERROR: No FPGA config found. Run 'make fpga' first."; \
		exit 1; \
	fi
	@mkdir -p "$(FPGA_BUILD_DIR)"
	@case "$(PROGRAM)" in \
		*.bin) $(PYTHON) scripts/bin2hex.py "$(PROGRAM)" "$(FPGA_PROGRAM_BYTEHEX)" ;; \
		*.hex) cp "$(PROGRAM)" "$(FPGA_PROGRAM_BYTEHEX)" ;; \
		*) echo "ERROR: PROGRAM must be .bin or byte-oriented .hex"; exit 1 ;; \
	esac
	@$(PYTHON) scripts/bytehex_to_wordhex.py "$(FPGA_PROGRAM_BYTEHEX)" "$(FPGA_PROGRAM_WORDHEX)" --depth $(FPGA_BRAM_DEPTH)
	@$(PYTHON) scripts/wordhex_split_banks.py "$(FPGA_PROGRAM_WORDHEX)" "$(FPGA_PROGRAM_BANK_PREFIX)"
	@set -e; CFG_IN="$(FPGA_BUILD_DIR)/$(FPGA_TOP).config"; \
	for BANK in 0 1 2 3; do \
		if [ "$$BANK" -eq 3 ]; then CFG_OUT="$(FPGA_PATCHED_CONFIG)"; else CFG_OUT="$(FPGA_BUILD_DIR)/core.bank$$BANK.config"; fi; \
		$(ECPBRAM) -v -i "$$CFG_IN" -o "$$CFG_OUT" \
			-f "$(FPGA_GARBAGE_BANK_PREFIX).bank$$BANK.wordhex" \
			-t "$(FPGA_PROGRAM_BANK_PREFIX).bank$$BANK.wordhex"; \
		CFG_IN="$$CFG_OUT"; \
	done
	@$(ECPPACK) --compress "$(FPGA_PATCHED_CONFIG)" "$(BITSTREAM)"
	@echo "[neo] patched bitstream ready: $(BITSTREAM)"

fpga-list: check-fpga
	$(call banner,FPGA SOURCE LIST)
	@$(PYTHON) $(SIM_HELPER) list \
		--filelist $(FPGA_FILELIST)

clean:
	$(call banner,CLEAN SIM)
	@$(PYTHON) $(SIM_HELPER) clean \
		--build-dir $(SIM_BUILD_DIR)

clobber:
	$(call banner,CLEAN ALL)
	@rm -rf $(BUILD_ROOT)
