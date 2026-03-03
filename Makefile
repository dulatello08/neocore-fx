PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
NEXTPNR ?= nextpnr-ecp5
ECPPACK ?= ecppack

SIM_HELPER := scripts/sim.py

BUILD_ROOT ?= build
SIM_BUILD_DIR ?= $(BUILD_ROOT)/sim
FPGA_BUILD_DIR ?= $(BUILD_ROOT)/fpga
WAVE_DIR ?= $(BUILD_ROOT)/waves

SIM_FILELIST ?= filelists/sim.f
SIM_TOP ?= tb_neocorefx_top
SIM_BIN ?= $(SIM_BUILD_DIR)/simv
IVERILOG_FLAGS ?= -g2012 -Wall -Winfloop
VVP_ARGS ?=

FPGA_FILELIST ?= filelists/fpga.f
FPGA_TOP ?= neocorefx_fpga_top
LPF ?= ulx3s-85f-min.lpf
ECP5_SIZE ?= 85k
ECP5_PACKAGE ?= CABGA381
ECP5_SPEED ?= 6
ECP5_FREQ ?= 25
BITSTREAM ?= $(FPGA_BUILD_DIR)/$(FPGA_TOP).bit

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

.PHONY: help check-sim check-fpga dirs build run waves list fpga fpga-list clean clobber

help:
	@printf "$(CLR_BOLD)$(CLR_BLUE)NeoCoreFX Build Targets$(CLR_RESET)\n"
	@printf "  $(CLR_GREEN)make build$(CLR_RESET)      Compile simulation binary (iverilog)\n"
	@printf "  $(CLR_GREEN)make run$(CLR_RESET)        Build + run simulation (vvp)\n"
	@printf "  $(CLR_GREEN)make waves$(CLR_RESET)      Build + run with +WAVES (VCD)\n"
	@printf "  $(CLR_GREEN)make list$(CLR_RESET)       Show resolved simulation source order\n"
	@printf "  $(CLR_GREEN)make fpga$(CLR_RESET)       Build FPGA bitstream (yosys/nextpnr/ecppack)\n"
	@printf "  $(CLR_GREEN)make fpga-list$(CLR_RESET)  Show resolved FPGA source order\n"
	@printf "  $(CLR_GREEN)make clean$(CLR_RESET)      Remove simulation build directory\n"
	@printf "  $(CLR_GREEN)make clobber$(CLR_RESET)    Remove full build directory\n"
	@printf "\n$(CLR_BOLD)Key Variables$(CLR_RESET)\n"
	@printf "  SIM_TOP=$(SIM_TOP)\n"
	@printf "  SIM_FILELIST=$(SIM_FILELIST)\n"
	@printf "  FPGA_TOP=$(FPGA_TOP)\n"
	@printf "  FPGA_FILELIST=$(FPGA_FILELIST)\n"
	@printf "  LPF=$(LPF)\n"
	@printf "  ECP5_SIZE=$(ECP5_SIZE) ECP5_PACKAGE=$(ECP5_PACKAGE) ECP5_SPEED=$(ECP5_SPEED)\n"

check-sim:
	@command -v $(PYTHON) >/dev/null
	@command -v $(IVERILOG) >/dev/null
	@command -v $(VVP) >/dev/null

check-fpga:
	@command -v $(PYTHON) >/dev/null
	@command -v $(YOSYS) >/dev/null
	@command -v $(NEXTPNR) >/dev/null
	@command -v $(ECPPACK) >/dev/null

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

fpga: check-fpga dirs
	$(call banner,FPGA BUILD)
	$(call note,Top: $(FPGA_TOP))
	$(call note,Constraints: $(LPF))
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
		--nextpnr $(NEXTPNR) \
		--ecppack $(ECPPACK) \
		--bit $(BITSTREAM)

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
