//
// neocorefx_fpga_top.sv
// NeoCoreFX - ULX3S board-level top
//

module neocorefx_fpga_top (
  // Board clock and button inputs.
  input  logic       clk_25mhz,
  input  logic [6:0] btn,
  input  logic       ftdi_txd,
  input  logic       ftdi_nrts,
  input  logic       ftdi_ndtr,
  input  logic       ftdi_txden,
  input  logic       ftdi_nrxled,
  output logic       ftdi_rxd,

  // User LEDs.
  output logic [7:0] led
);
  timeunit 1ns;
  timeprecision 1ps;

  logic [7:0] status_count;
  logic halted;
  logic [31:0] current_pc;
  logic [31:0] cycle_count;
  logic [31:0] retire_count;
  logic [31:0] branch_redirect_count;
  logic [31:0] load_stall_count;
  logic [31:0] mem_stall_count;
  logic wb_fault;

  logic clk_40mhz;
  logic pll_locked;
  logic soc_rst_btn_n;
  logic btn0_sync_ff1 = 1'b0;
  logic btn0_sync_ff2 = 1'b0;
  logic rst_btn_n_q = 1'b0;
  logic [18:0] rst_hold_ctr_q = 19'd400_000;
  logic [24:0] heartbeat;
  logic unused_ftdi_inputs;

  localparam int unsigned RST_HOLD_CYCLES = 19'd400_000; // 10 ms @ 40 MHz.

  neocorefx_pll_40mhz u_pll (
    .clk_i    (clk_25mhz),
    .clk_o    (clk_40mhz),
    .locked_o (pll_locked)
  );

  assign soc_rst_btn_n = rst_btn_n_q;
  assign unused_ftdi_inputs = ftdi_nrts ^ ftdi_ndtr ^ ftdi_txden ^ ftdi_nrxled;

  // Keep a free-running heartbeat separate from core status.
  always_ff @(posedge clk_40mhz) begin
    heartbeat <= heartbeat + 25'd1;
  end

  // Reset conditioner:
  // - synchronize raw button into clk_40mhz domain
  // - assert reset immediately on button press
  // - hold reset low for a fixed interval after release to absorb bounce
  always_ff @(posedge clk_40mhz) begin
    btn0_sync_ff1 <= btn[0];
    btn0_sync_ff2 <= btn0_sync_ff1;

    if (!pll_locked) begin
      rst_btn_n_q <= 1'b0;
      rst_hold_ctr_q <= RST_HOLD_CYCLES;
    end else if (!btn0_sync_ff2) begin
      rst_btn_n_q <= 1'b0;
      rst_hold_ctr_q <= RST_HOLD_CYCLES;
    end else if (rst_hold_ctr_q != 0) begin
      rst_btn_n_q <= 1'b0;
      rst_hold_ctr_q <= rst_hold_ctr_q - 19'd1;
    end else begin
      rst_btn_n_q <= 1'b1;
    end
  end

  neocorefx_top u_soc (
    .clk                    (clk_40mhz),
    .rst_btn_n              (soc_rst_btn_n),
    .uart_rx_i              (ftdi_txd),
    .uart_tx_o              (ftdi_rxd),
    .en                     (1'b1),
    .count                  (status_count),
    .halted_o               (halted),
    .current_pc_o           (current_pc),
    .cycle_count_o          (cycle_count),
    .retire_count_o         (retire_count),
    .branch_redirect_count_o(branch_redirect_count),
    .load_stall_count_o     (load_stall_count),
    .mem_stall_count_o      (mem_stall_count),
    .wb_fault_o             (wb_fault)
  );

  // LED layout is tuned for quick bench-top bring-up.
  always_ff @(posedge clk_40mhz) begin
    led[7] <= !btn[0];      // Reset asserted.
    led[6] <= heartbeat[24];       // Alive heartbeat @ 40 MHz domain.
    led[5] <= !pll_locked;         // PLL lock indicator.
    led[4] <= wb_fault;            // Fault pulse sticky state from WB.
    led[3] <= halted;              // Halt retired.
    led[2] <= current_pc[3];       // PC movement.
    led[1] <= status_count[4];     // MEM stall activity.1
    led[0] <= status_count[3];     // Load-use stall activity.
  end

  logic unused_pc;
  assign unused_pc = current_pc[2];

  logic unused_ftdi_mix;
  assign unused_ftdi_mix = unused_ftdi_inputs ^ current_pc[0];
endmodule : neocorefx_fpga_top
