//
// neocorefx_core.sv
// NeoCoreFX - Integrated 6-stage core
//

module neocorefx_core
  import core_pkg::*;
(
  input  logic        clk,
  input  logic        rst,
  input  logic        run_i,
  input  logic        dbg_halt_req_i,
  input  logic        dbg_resume_req_i,
  input  logic        dbg_step_req_i,
  input  logic        dbg_pc_set_req_i,
  input  logic [31:0] dbg_pc_set_i,
  input  logic [3:0]  dbg_gpr_addr_i,
  output logic [31:0] dbg_gpr_rdata_o,
  input  logic        dbg_gpr_we_i,
  input  logic [31:0] dbg_gpr_wdata_i,

  output logic        i_req_o,
  output logic [31:0] i_addr_o,
  input  logic        i_busy_i,
  input  logic        i_done_i,
  input  logic [31:0] i_rdata_i,
  input  logic        i_err_i,

  output logic        d_req_o,
  output logic        d_we_o,
  output logic [1:0]  d_size_o,
  output logic [31:0] d_addr_o,
  output logic [31:0] d_wdata_o,
  input  logic        d_busy_i,
  input  logic        d_done_i,
  input  logic [31:0] d_rdata_i,
  input  logic        d_err_i,

  output logic        halted_o,
  output logic [31:0] current_pc_o,
  output logic [2:0]  dbg_halt_reason_o,
  output logic        dbg_last_fault_o,
  output logic [31:0] dbg_last_fault_pc_o,
  output logic [31:0] dbg_last_fault_addr_o,
  output logic [31:0] dbg_last_illegal_inst_o,

  output logic        wb_valid_o,
  output logic        wb_fault_o,
  output logic        load_use_stall_o,
  output logic        mem_wait_stall_o,
  output logic        mispredict_o,

  output logic [31:0] cycle_count_o,
  output logic [31:0] retire_count_o,
  output logic [31:0] branch_redirect_count_o,
  output logic [31:0] load_stall_count_o,
  output logic [31:0] mem_stall_count_o
);
  timeunit 1ns;
  timeprecision 1ps;

  typedef enum logic [1:0] {
    DBG_RUN          = 2'd0,
    DBG_HALT_PENDING = 2'd1,
    DBG_HALTED       = 2'd2,
    DBG_STEP_PENDING = 2'd3
  } dbg_state_t;

  localparam logic [2:0] HALT_REASON_NONE       = 3'd0;
  localparam logic [2:0] HALT_REASON_B_DOT      = 3'd1;
  localparam logic [2:0] HALT_REASON_DEBUG_REQ  = 3'd2;
  localparam logic [2:0] HALT_REASON_DEBUG_STEP = 3'd3;

  dbg_state_t   dbg_state_q;
  logic [2:0]   halt_reason_q;
  logic         last_fault_q;
  logic [31:0]  last_fault_pc_q;
  logic [31:0]  last_fault_addr_q;
  logic [31:0]  last_illegal_inst_q;

  logic         core_halted;
  logic         can_halt_boundary;
  logic [31:0]  dbg_gpr_rdata;
  logic         dbg_gpr_we;

  logic [31:0]  if1_pc;
  logic [31:0]  dbg_pc_shadow_q;
  logic [3:0]   rf_rs1_addr;
  logic [3:0]   rf_rs2_addr;
  logic [31:0]  rf_rs1_data;
  logic [31:0]  rf_rs2_data;
  logic         rf_we;
  logic [3:0]   rf_waddr;
  logic [31:0]  rf_wdata;

  logic         load_use_stall;
  logic         mem_stall_req;
  logic         mem_wait_stall;
  logic         redirect_valid;
  logic [31:0]  redirect_pc;
  logic         mispredict;

  logic         idex_valid;
  logic [31:0]  idex_pc;
  logic [3:0]   idex_rd;
  logic [3:0]   idex_rs1_addr;
  logic [31:0]  idex_imm;
  logic         idex_pred_taken;
  logic [2:0]   idex_branch_type;
  logic         idex_is_jal;
  logic         idex_is_jalr;
  logic [31:0]  idex_inst;
  logic         idex_illegal;

  logic         wb_valid;
  logic         wb_fault;
  logic         wb_halted_pulse;

  logic         core_hold;
  logic         if1_stall;
  logic         if2_stall;
  logic         id_stall;
  logic         id_flush;
  logic         id_bubble;
  logic         exe_stall;
  logic         exe_flush;
  logic         mem_stall;
  logic         mem_flush;
  logic         if2_flush;

  logic         dbg_redirect_valid;
  logic [31:0]  dbg_redirect_pc;
  logic         if1_redirect_valid;
  logic [31:0]  if1_redirect_pc;

  logic         bp_update_valid;
  logic [31:0]  bp_update_pc;
  logic         bp_update_taken;
  logic         ras_push_valid;
  logic [31:0]  ras_push_addr;
  logic         ras_pop_valid;

  logic [31:0] cycle_count;
  logic [31:0] retire_count;
  logic [31:0] branch_redirect_count;
  logic [31:0] load_stall_count;
  logic [31:0] mem_stall_count;

  assign mem_wait_stall = mem_stall_req;
  assign core_halted = (dbg_state_q == DBG_HALTED);

  neocorefx_core_control u_ctrl (
    .run_i               (run_i),
    .dbg_gpr_we_i        (dbg_gpr_we_i),
    .dbg_pc_set_req_i    (dbg_pc_set_req_i),
    .dbg_pc_set_i        (dbg_pc_set_i),
    .core_halted_i       (core_halted),
    .wb_valid_i          (wb_valid),
    .mem_wait_stall_i    (mem_wait_stall),
    .load_use_stall_i    (load_use_stall),
    .redirect_valid_i    (redirect_valid),
    .redirect_pc_i       (redirect_pc),
    .mispredict_i        (mispredict),
    .idex_valid_i        (idex_valid),
    .idex_illegal_i      (idex_illegal),
    .idex_branch_type_i  (idex_branch_type),
    .idex_pc_i           (idex_pc),
    .idex_pred_taken_i   (idex_pred_taken),
    .idex_rd_i           (idex_rd),
    .idex_is_jal_i       (idex_is_jal),
    .idex_is_jalr_i      (idex_is_jalr),
    .idex_rs1_addr_i     (idex_rs1_addr),
    .idex_imm_i          (idex_imm),
    .can_halt_boundary_o (can_halt_boundary),
    .core_hold_o         (core_hold),
    .dbg_gpr_we_o        (dbg_gpr_we),
    .if1_stall_o         (if1_stall),
    .if2_stall_o         (if2_stall),
    .if2_flush_o         (if2_flush),
    .id_stall_o          (id_stall),
    .id_flush_o          (id_flush),
    .id_bubble_o         (id_bubble),
    .exe_stall_o         (exe_stall),
    .exe_flush_o         (exe_flush),
    .mem_stall_o         (mem_stall),
    .mem_flush_o         (mem_flush),
    .dbg_redirect_valid_o(dbg_redirect_valid),
    .dbg_redirect_pc_o   (dbg_redirect_pc),
    .if1_redirect_valid_o(if1_redirect_valid),
    .if1_redirect_pc_o   (if1_redirect_pc),
    .bp_update_valid_o   (bp_update_valid),
    .bp_update_pc_o      (bp_update_pc),
    .bp_update_taken_o   (bp_update_taken),
    .ras_push_valid_o    (ras_push_valid),
    .ras_push_addr_o     (ras_push_addr),
    .ras_pop_valid_o     (ras_pop_valid)
  );

  neocorefx_core_stages u_stages (
    .clk                 (clk),
    .rst                 (rst),
    .if1_stall_i         (if1_stall),
    .if2_stall_i         (if2_stall),
    .if2_flush_i         (if2_flush),
    .id_stall_i          (id_stall),
    .id_flush_i          (id_flush),
    .id_bubble_i         (id_bubble),
    .exe_stall_i         (exe_stall),
    .exe_flush_i         (exe_flush),
    .mem_stall_i         (mem_stall),
    .mem_flush_i         (mem_flush),
    .if1_redirect_valid_i(if1_redirect_valid),
    .if1_redirect_pc_i   (if1_redirect_pc),
    .bp_update_valid_i   (bp_update_valid),
    .bp_update_pc_i      (bp_update_pc),
    .bp_update_taken_i   (bp_update_taken),
    .ras_push_valid_i    (ras_push_valid),
    .ras_push_addr_i     (ras_push_addr),
    .ras_pop_valid_i     (ras_pop_valid),
    .i_req_o             (i_req_o),
    .i_addr_o            (i_addr_o),
    .i_done_i            (i_done_i),
    .i_rdata_i           (i_rdata_i),
    .i_err_i             (i_err_i),
    .d_req_o             (d_req_o),
    .d_we_o              (d_we_o),
    .d_size_o            (d_size_o),
    .d_addr_o            (d_addr_o),
    .d_wdata_o           (d_wdata_o),
    .d_done_i            (d_done_i),
    .d_rdata_i           (d_rdata_i),
    .d_err_i             (d_err_i),
    .rf_rs1_addr_o       (rf_rs1_addr),
    .rf_rs2_addr_o       (rf_rs2_addr),
    .rf_rs1_data_i       (rf_rs1_data),
    .rf_rs2_data_i       (rf_rs2_data),
    .rf_we_o             (rf_we),
    .rf_waddr_o          (rf_waddr),
    .rf_wdata_o          (rf_wdata),
    .if1_pc_o            (if1_pc),
    .load_use_stall_o    (load_use_stall),
    .mem_stall_req_o     (mem_stall_req),
    .redirect_valid_o    (redirect_valid),
    .redirect_pc_o       (redirect_pc),
    .mispredict_o        (mispredict),
    .idex_valid_o        (idex_valid),
    .idex_pc_o           (idex_pc),
    .idex_rd_o           (idex_rd),
    .idex_rs1_addr_o     (idex_rs1_addr),
    .idex_imm_o          (idex_imm),
    .idex_pred_taken_o   (idex_pred_taken),
    .idex_branch_type_o  (idex_branch_type),
    .idex_is_jal_o       (idex_is_jal),
    .idex_is_jalr_o      (idex_is_jalr),
    .idex_inst_o         (idex_inst),
    .idex_illegal_o      (idex_illegal),
    .wb_valid_o          (wb_valid),
    .wb_fault_o          (wb_fault),
    .wb_halted_pulse_o   (wb_halted_pulse)
  );

  regfile u_regfile (
    .clk                 (clk),
    .rst                 (rst),
    .rs1_addr_i          (rf_rs1_addr),
    .rs2_addr_i          (rf_rs2_addr),
    .rs1_data_o          (rf_rs1_data),
    .rs2_data_o          (rf_rs2_data),
    .we_i                (rf_we),
    .waddr_i             (rf_waddr),
    .wdata_i             (rf_wdata),
    .dbg_raddr_i         (dbg_gpr_addr_i),
    .dbg_rdata_o         (dbg_gpr_rdata),
    .dbg_we_i            (dbg_gpr_we),
    .dbg_waddr_i         (dbg_gpr_addr_i),
    .dbg_wdata_i         (dbg_gpr_wdata_i)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      dbg_state_q <= DBG_RUN;
      halt_reason_q <= HALT_REASON_NONE;
      last_fault_q <= 1'b0;
      last_fault_pc_q <= 32'h0000_0000;
      last_fault_addr_q <= 32'h0000_0000;
      last_illegal_inst_q <= 32'h0000_0000;
    end else begin
      if (idex_valid && idex_illegal) begin
        last_illegal_inst_q <= idex_inst;
      end

      if (wb_fault) begin
        last_fault_q <= 1'b1;
        last_fault_pc_q <= if1_pc;
      end

      if (d_req_o && d_done_i && d_err_i) begin
        last_fault_addr_q <= d_addr_o;
      end

      unique case (dbg_state_q)
        DBG_RUN: begin
          if (wb_halted_pulse) begin
            dbg_state_q <= DBG_HALTED;
            halt_reason_q <= HALT_REASON_B_DOT;
          end else if (dbg_halt_req_i) begin
            dbg_state_q <= DBG_HALT_PENDING;
            halt_reason_q <= HALT_REASON_DEBUG_REQ;
          end
        end
        DBG_HALT_PENDING: begin
          if (wb_halted_pulse) begin
            dbg_state_q <= DBG_HALTED;
            halt_reason_q <= HALT_REASON_B_DOT;
          end else if (dbg_resume_req_i) begin
            dbg_state_q <= DBG_RUN;
            halt_reason_q <= HALT_REASON_NONE;
          end else if (can_halt_boundary) begin
            dbg_state_q <= DBG_HALTED;
          end
        end
        DBG_HALTED: begin
          if (dbg_resume_req_i) begin
            dbg_state_q <= DBG_RUN;
            halt_reason_q <= HALT_REASON_NONE;
          end else if (dbg_step_req_i) begin
            dbg_state_q <= DBG_STEP_PENDING;
            halt_reason_q <= HALT_REASON_DEBUG_STEP;
          end
        end
        default: begin
          if (wb_halted_pulse) begin
            dbg_state_q <= DBG_HALTED;
            halt_reason_q <= HALT_REASON_B_DOT;
          end else if (dbg_halt_req_i) begin
            dbg_state_q <= DBG_HALT_PENDING;
            halt_reason_q <= HALT_REASON_DEBUG_REQ;
          end else if (can_halt_boundary) begin
            dbg_state_q <= DBG_HALTED;
            halt_reason_q <= HALT_REASON_DEBUG_STEP;
          end
        end
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      cycle_count <= 32'h0000_0000;
      retire_count <= 32'h0000_0000;
      branch_redirect_count <= 32'h0000_0000;
      load_stall_count <= 32'h0000_0000;
      mem_stall_count <= 32'h0000_0000;
    end else if (run_i && !core_halted) begin
      cycle_count <= cycle_count + 32'd1;
      if (wb_valid) retire_count <= retire_count + 32'd1;
      if (redirect_valid) branch_redirect_count <= branch_redirect_count + 32'd1;
      if (load_use_stall) load_stall_count <= load_stall_count + 32'd1;
      if (mem_wait_stall) mem_stall_count <= mem_stall_count + 32'd1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      dbg_pc_shadow_q <= 32'h0000_0000;
    end else if (dbg_redirect_valid) begin
      dbg_pc_shadow_q <= dbg_redirect_pc;
    end else if (!core_halted) begin
      dbg_pc_shadow_q <= if1_pc;
    end
  end

  assign halted_o = core_halted;
  assign current_pc_o = core_halted ? dbg_pc_shadow_q : if1_pc;
  assign dbg_gpr_rdata_o = dbg_gpr_rdata;
  assign dbg_halt_reason_o = halt_reason_q;
  assign dbg_last_fault_o = last_fault_q;
  assign dbg_last_fault_pc_o = last_fault_pc_q;
  assign dbg_last_fault_addr_o = last_fault_addr_q;
  assign dbg_last_illegal_inst_o = last_illegal_inst_q;

  assign wb_valid_o = wb_valid;
  assign wb_fault_o = wb_fault;
  assign load_use_stall_o = load_use_stall;
  assign mem_wait_stall_o = mem_wait_stall;
  assign mispredict_o = mispredict;

  assign cycle_count_o = cycle_count;
  assign retire_count_o = retire_count;
  assign branch_redirect_count_o = branch_redirect_count;
  assign load_stall_count_o = load_stall_count;
  assign mem_stall_count_o = mem_stall_count;

  logic unused_biu_busy;
  assign unused_biu_busy = i_busy_i ^ d_busy_i;
endmodule
