//
// neocorefx_top.sv
// NeoCoreFX - Integrated core + BIU + BRAM top wrapper
//

module neocorefx_top (
  // Clock/reset controls.
  input  logic       clk,
  input  logic       rst_btn_n,
  input  logic       uart_rx_i,
  output logic       uart_tx_o,

  // External run enable.
  input  logic       en,

  // Compact status output.
  output logic [7:0] count,

  // Optional observability outputs.
  output logic       halted_o,
  output logic [31:0] current_pc_o,
  output logic [31:0] cycle_count_o,
  output logic [31:0] retire_count_o,
  output logic [31:0] branch_redirect_count_o,
  output logic [31:0] load_stall_count_o,
  output logic [31:0] mem_stall_count_o,
  output logic       wb_fault_o
);
  timeunit 1ns;
  timeprecision 1ps;

  // ============================================================================
  // Reset and run control
  // ============================================================================

  logic rst;
  assign rst = !rst_btn_n;

  // ============================================================================
  // Core <-> BIU wiring
  // ============================================================================

  logic        core_i_req;
  logic [31:0] core_i_addr;
  logic        core_i_busy;
  logic        core_i_done;
  logic [31:0] core_i_rdata;
  logic        core_i_err;

  logic        core_d_req;
  logic        core_d_we;
  logic [1:0]  core_d_size;
  logic [31:0] core_d_addr;
  logic [31:0] core_d_wdata;
  logic        core_d_busy;
  logic        core_d_done;
  logic [31:0] core_d_rdata;
  logic        core_d_err;

  // ============================================================================
  // BIU <-> memory wiring
  // ============================================================================

  logic        ibus_cyc;
  logic        ibus_stb;
  logic [31:0] ibus_addr;
  logic        ibus_ack;
  logic [31:0] ibus_rdata;
  logic        ibus_err;

  logic        dbus_cyc;
  logic        dbus_stb;
  logic        dbus_we;
  logic [31:0] dbus_addr;
  logic [31:0] dbus_wdata;
  logic [3:0]  dbus_sel;
  logic        dbus_ack;
  logic [31:0] dbus_rdata;
  logic        dbus_err;

  // ============================================================================
  // Core status/profiling
  // ============================================================================

  logic halted;
  logic [31:0] current_pc;
  logic wb_valid;
  logic wb_fault;
  logic load_use_stall;
  logic mem_wait_stall;
  logic mispredict;

  logic [31:0] cycle_count;
  logic [31:0] retire_count;
  logic [31:0] branch_redirect_count;
  logic [31:0] load_stall_count;
  logic [31:0] mem_stall_count;

  // ============================================================================
  // Instances
  // ============================================================================

  neocorefx_core u_core (
    .clk                    (clk),
    .rst                    (rst),
    .run_i                  (en),
    .i_req_o                (core_i_req),
    .i_addr_o               (core_i_addr),
    .i_busy_i               (core_i_busy),
    .i_done_i               (core_i_done),
    .i_rdata_i              (core_i_rdata),
    .i_err_i                (core_i_err),
    .d_req_o                (core_d_req),
    .d_we_o                 (core_d_we),
    .d_size_o               (core_d_size),
    .d_addr_o               (core_d_addr),
    .d_wdata_o              (core_d_wdata),
    .d_busy_i               (core_d_busy),
    .d_done_i               (core_d_done),
    .d_rdata_i              (core_d_rdata),
    .d_err_i                (core_d_err),
    .halted_o               (halted),
    .current_pc_o           (current_pc),
    .wb_valid_o             (wb_valid),
    .wb_fault_o             (wb_fault),
    .load_use_stall_o       (load_use_stall),
    .mem_wait_stall_o       (mem_wait_stall),
    .mispredict_o           (mispredict),
    .cycle_count_o          (cycle_count),
    .retire_count_o         (retire_count),
    .branch_redirect_count_o(branch_redirect_count),
    .load_stall_count_o     (load_stall_count),
    .mem_stall_count_o      (mem_stall_count)
  );

  biu u_biu (
    .clk                    (clk),
    .rst                    (rst),
    .i_req                  (core_i_req),
    .i_addr                 (core_i_addr),
    .i_busy                 (core_i_busy),
    .i_done                 (core_i_done),
    .i_rdata                (core_i_rdata),
    .i_err                  (core_i_err),
    .d_req                  (core_d_req),
    .d_we                   (core_d_we),
    .d_size                 (core_d_size),
    .d_addr                 (core_d_addr),
    .d_wdata                (core_d_wdata),
    .d_busy                 (core_d_busy),
    .d_done                 (core_d_done),
    .d_rdata                (core_d_rdata),
    .d_err                  (core_d_err),
    .ibus_cyc               (ibus_cyc),
    .ibus_stb               (ibus_stb),
    .ibus_addr              (ibus_addr),
    .ibus_ack               (ibus_ack),
    .ibus_rdata             (ibus_rdata),
    .ibus_err               (ibus_err),
    .dbus_cyc               (dbus_cyc),
    .dbus_stb               (dbus_stb),
    .dbus_we                (dbus_we),
    .dbus_addr              (dbus_addr),
    .dbus_wdata             (dbus_wdata),
    .dbus_sel               (dbus_sel),
    .dbus_ack               (dbus_ack),
    .dbus_rdata             (dbus_rdata),
    .dbus_err               (dbus_err)
  );

  mem u_mem (
    .clk                    (clk),
    .rst                    (rst),
    .ibus_cyc               (ibus_cyc),
    .ibus_stb               (ibus_stb),
    .ibus_addr              (ibus_addr),
    .ibus_ack               (ibus_ack),
    .ibus_rdata             (ibus_rdata),
    .ibus_err               (ibus_err),
    .dbus_cyc               (dbus_cyc),
    .dbus_stb               (dbus_stb),
    .dbus_we                (dbus_we),
    .dbus_addr              (dbus_addr),
    .dbus_wdata             (dbus_wdata),
    .dbus_sel               (dbus_sel),
    .dbus_ack               (dbus_ack),
    .dbus_rdata             (dbus_rdata),
    .dbus_err               (dbus_err),
    .uart_rx_i              (uart_rx_i),
    .uart_tx_o              (uart_tx_o)
  );

  // ============================================================================
  // Status exposure
  // ============================================================================

  assign halted_o = halted;
  assign current_pc_o = current_pc;
  assign cycle_count_o = cycle_count;
  assign retire_count_o = retire_count;
  assign branch_redirect_count_o = branch_redirect_count;
  assign load_stall_count_o = load_stall_count;
  assign mem_stall_count_o = mem_stall_count;
  assign wb_fault_o = wb_fault;

  // 8-bit board-friendly signature.
  always_comb begin
    count[7] = halted;
    count[6] = wb_fault;
    count[5] = mispredict;
    count[4] = mem_wait_stall;
    count[3] = load_use_stall;
    count[2] = wb_valid;
    count[1] = current_pc[2];
    count[0] = current_pc[1];
  end
endmodule : neocorefx_top
