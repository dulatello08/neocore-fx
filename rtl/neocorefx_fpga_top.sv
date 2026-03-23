//
// neocorefx_fpga_top.sv
// NeoCoreFX - ULX3S board-level top
//

module neocorefx_fpga_top (
  // Board clock and button inputs.
  input  logic       clk_25mhz,
  input  logic [6:0] btn,

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

  logic [24:0] heartbeat;
  logic uart_tx_unused;

  // Keep a free-running heartbeat separate from core status.
  always_ff @(posedge clk_25mhz) begin
    heartbeat <= heartbeat + 25'd1;
  end

  neocorefx_top u_soc (
    .clk                    (clk_25mhz),
    .rst_btn_n              (btn[0]),
    .uart_rx_i              (1'b1),
    .uart_tx_o              (uart_tx_unused),
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
  always_comb begin
    led[7] = !btn[0];             // Reset asserted.
    led[6] = heartbeat[24];       // Alive heartbeat.
    led[5] = halted;              // Halt retired.
    led[4] = wb_fault;            // Fault pulse sticky state from WB.
    led[3] = current_pc[3];       // PC movement.
    led[2] = current_pc[2];
    led[1] = status_count[4];     // MEM stall activity.
    led[0] = status_count[3];     // Load-use stall activity.
  end
endmodule : neocorefx_fpga_top
