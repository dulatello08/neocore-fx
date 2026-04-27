//
// neocorefx_core.sv
// NeoCoreFX - Integrated 6-stage core
//
// Integrates IF1/IF2/ID/EXE/MEM/WB with register file and external BIU ports.
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

  // BIU instruction response/request channel.
  output logic        i_req_o,
  output logic [31:0] i_addr_o,
  input  logic        i_busy_i,
  input  logic        i_done_i,
  input  logic [31:0] i_rdata_i,
  input  logic        i_err_i,

  // BIU data response/request channel.
  output logic        d_req_o,
  output logic        d_we_o,
  output logic [1:0]  d_size_o,
  output logic [31:0] d_addr_o,
  output logic [31:0] d_wdata_o,
  input  logic        d_busy_i,
  input  logic        d_done_i,
  input  logic [31:0] d_rdata_i,
  input  logic        d_err_i,

  // Core status.
  output logic        halted_o,
  output logic [31:0] current_pc_o,
  output logic [2:0]  dbg_halt_reason_o,
  output logic        dbg_last_fault_o,
  output logic [31:0] dbg_last_fault_pc_o,
  output logic [31:0] dbg_last_fault_addr_o,
  output logic [31:0] dbg_last_illegal_inst_o,

  // Profiling/status pulses.
  output logic        wb_valid_o,
  output logic        wb_fault_o,
  output logic        load_use_stall_o,
  output logic        mem_wait_stall_o,
  output logic        mispredict_o,

  // Profiling counters.
  output logic [31:0] cycle_count_o,
  output logic [31:0] retire_count_o,
  output logic [31:0] branch_redirect_count_o,
  output logic [31:0] load_stall_count_o,
  output logic [31:0] mem_stall_count_o
);
  timeunit 1ns;
  timeprecision 1ps;

  // ============================================================================
  // Pipeline control fabric
  // ============================================================================

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

  logic core_hold;
  logic if1_stall;
  logic if2_stall;
  logic id_stall;
  logic id_flush;
  logic id_bubble;
  logic exe_stall;
  logic exe_flush;
  logic mem_stall;
  logic mem_flush;
  logic if2_flush;

  logic load_use_stall;
  logic mem_wait_stall;

  // ============================================================================
  // IF1 -> IF2 wires
  // ============================================================================

  logic        if2_if1_valid;
  logic [31:0] if2_if1_pc;
  logic        if2_if1_pred_taken;

  logic        pred_valid;
  logic        pred_taken;
  logic [31:0] pred_target;
  logic        bp_update_valid;
  logic [31:0] bp_update_pc;
  logic        bp_update_taken;
  logic        ras_push_valid;
  logic [31:0] ras_push_addr;
  logic        ras_pop_valid;

  logic [31:0] if1_pc;
  logic [31:0] dbg_pc_shadow_q;
  logic        dbg_redirect_valid;
  logic [31:0] dbg_redirect_pc;
  logic        if1_redirect_valid;
  logic [31:0] if1_redirect_pc;

  // ============================================================================
  // IF2 -> ID wires
  // ============================================================================

  logic        id_if2_valid;
  logic [31:0] id_if2_pc;
  logic [31:0] id_if2_inst;
  logic        id_if2_pred_taken;
  logic [31:0] id_if2_pred_target;
  logic        id_if2_fetch_fault;

  // ============================================================================
  // ID -> EXE wires
  // ============================================================================

  logic [3:0]  rf_rs1_addr;
  logic [3:0]  rf_rs2_addr;
  logic [31:0] rf_rs1_data;
  logic [31:0] rf_rs2_data;

  logic        idex_valid;
  logic [31:0] idex_pc;
  logic [3:0]  idex_rd;
  logic [3:0]  idex_rs1_addr;
  logic [3:0]  idex_rs2_addr;
  logic [31:0] idex_rs1_data;
  logic [31:0] idex_rs2_data;
  logic [31:0] idex_inst;
  logic [31:0] idex_imm;
  logic [4:0]  idex_alu_op;
  logic        idex_alu_src_imm;
  logic        idex_mem_read;
  logic        idex_mem_write;
  logic [1:0]  idex_mem_size;
  logic        idex_load_sign_ext;
  logic        idex_reg_write;
  logic [2:0]  idex_branch_type;
  logic        idex_is_jal;
  logic        idex_is_jalr;
  logic        idex_is_lui;
  logic        idex_is_lpc;
  logic        idex_is_halt;
  logic        idex_pred_taken;
  logic [31:0] idex_pred_target;
  logic        idex_fetch_fault;
  logic [1:0]  idex_fwd_rs1_sel;
  logic [1:0]  idex_fwd_rs2_sel;
  logic        idex_illegal;

  // ============================================================================
  // EXE -> MEM wires
  // ============================================================================

  logic        redirect_valid;
  logic [31:0] redirect_pc;
  logic        mispredict;

  logic        exe_mem_valid;
  logic [3:0]  exe_mem_rd;
  logic [3:0]  exe_mem_store_rs2_addr;
  logic        exe_mem_reg_write;
  logic        exe_mem_mem_read;
  logic        exe_mem_mem_write;
  logic [1:0]  exe_mem_mem_size;
  logic        exe_mem_load_sign_ext;
  logic [31:0] exe_mem_result;
  logic [31:0] exe_mem_store_data;
  logic        exe_mem_fetch_fault;
  logic        exe_mem_illegal;
  logic        exe_mem_is_halt;

  // ============================================================================
  // MEM -> WB wires
  // ============================================================================

  logic        memwb_valid;
  logic [3:0]  memwb_rd;
  logic        memwb_reg_write;
  logic [31:0] memwb_data;
  logic        memwb_mem_fault;
  logic        memwb_fetch_fault;
  logic        memwb_illegal;
  logic        memwb_is_halt;

  logic        mem_stall_req;

  // ============================================================================
  // WB + register file wires
  // ============================================================================

  logic        rf_we;
  logic [3:0]  rf_waddr;
  logic [31:0] rf_wdata;

  logic        wb_valid;
  logic        wb_fault;
  logic        wb_halted_pulse;

  // ============================================================================
  // Profiling counters
  // ============================================================================

  logic [31:0] cycle_count;
  logic [31:0] retire_count;
  logic [31:0] branch_redirect_count;
  logic [31:0] load_stall_count;
  logic [31:0] mem_stall_count;
  localparam logic [3:0] ABI_LR_REG = 4'hB;

  // ============================================================================
  // Control policy
  // ============================================================================

  assign mem_wait_stall = mem_stall_req;
  assign load_use_stall = load_use_stall_o;

  assign core_halted = (dbg_state_q == DBG_HALTED);
  assign can_halt_boundary = wb_valid && !mem_wait_stall;
  assign dbg_redirect_valid = dbg_pc_set_req_i && core_halted;
  assign dbg_redirect_pc = {dbg_pc_set_i[31:2], 2'b00};
  assign if1_redirect_valid = redirect_valid || dbg_redirect_valid;
  assign if1_redirect_pc = redirect_valid ? redirect_pc : dbg_redirect_pc;

  // "Pulseflow" control style: frontend can freeze while backend drains.
  assign core_hold = !run_i || core_halted;
  assign dbg_gpr_we = dbg_gpr_we_i && core_halted;

  assign if1_stall = core_hold || mem_wait_stall || load_use_stall;
  assign if2_stall = core_hold || mem_wait_stall || load_use_stall;
  assign if2_flush = mispredict;

  assign id_stall = core_hold || mem_wait_stall;
  assign id_flush = mispredict;
  assign id_bubble = load_use_stall && !core_hold && !mem_wait_stall;

  assign exe_stall = core_hold || mem_wait_stall;
  assign exe_flush = 1'b0;

  assign mem_stall = core_hold;
  assign mem_flush = 1'b0;

  // Train IF2 dynamic predictor only from resolved conditional branches.
  // Branches in EXE resolve as: actual_taken = pred_taken ^ mispredict.
  assign bp_update_valid = idex_valid
                        && !exe_stall
                        && !idex_illegal
                        && ((idex_branch_type == BR_EQ)
                         || (idex_branch_type == BR_NE)
                         || (idex_branch_type == BR_LT)
                         || (idex_branch_type == BR_LTU));
  assign bp_update_pc = idex_pc;
  assign bp_update_taken = idex_pred_taken ^ mispredict;

  // Maintain IF2 return-address stack from resolved jumps in EXE.
  assign ras_push_valid = idex_valid
                       && !exe_stall
                       && !idex_illegal
                       && (idex_rd == ABI_LR_REG)
                       && (idex_is_jal || idex_is_jalr);
  assign ras_push_addr = idex_pc + 32'd4;
  assign ras_pop_valid = idex_valid
                      && !exe_stall
                      && !idex_illegal
                      && idex_is_jalr
                      && (idex_rd == 4'h0)
                      && (idex_rs1_addr == ABI_LR_REG)
                      && (idex_imm == 32'h0000_0000);

  // ============================================================================
  // Stage instances
  // ============================================================================

  if1_stage u_if1 (
    .clk                (clk),
    .rst                (rst),
    .stall_i            (if1_stall),
    .redirect_valid_i   (if1_redirect_valid),
    .redirect_pc_i      (if1_redirect_pc),
    .pred_valid_i       (pred_valid),
    .pred_taken_i       (pred_taken),
    .pred_target_i      (pred_target),
    .i_req_o            (i_req_o),
    .i_addr_o           (i_addr_o),
    .if2_valid_o        (if2_if1_valid),
    .if2_pc_o           (if2_if1_pc),
    .if2_pred_taken_o   (if2_if1_pred_taken),
    .pc_o               (if1_pc)
  );

  if2_stage u_if2 (
    .clk                (clk),
    .rst                (rst),
    .stall_i            (if2_stall),
    .flush_i            (if2_flush),
    .if1_valid_i        (if2_if1_valid),
    .if1_pc_i           (if2_if1_pc),
    .if1_pred_taken_i   (if2_if1_pred_taken),
    .bp_update_valid_i  (bp_update_valid),
    .bp_update_pc_i     (bp_update_pc),
    .bp_update_taken_i  (bp_update_taken),
    .ras_push_valid_i   (ras_push_valid),
    .ras_push_addr_i    (ras_push_addr),
    .ras_pop_valid_i    (ras_pop_valid),
    .i_done_i           (i_done_i),
    .i_rdata_i          (i_rdata_i),
    .i_err_i            (i_err_i),
    .id_valid_o         (id_if2_valid),
    .id_pc_o            (id_if2_pc),
    .id_inst_o          (id_if2_inst),
    .id_pred_taken_o    (id_if2_pred_taken),
    .id_pred_target_o   (id_if2_pred_target),
    .id_fetch_fault_o   (id_if2_fetch_fault),
    .pred_valid_o       (pred_valid),
    .pred_taken_o       (pred_taken),
    .pred_target_o      (pred_target)
  );

  id_stage u_id (
    .clk                (clk),
    .rst                (rst),
    .stall_i            (id_stall),
    .flush_i            (id_flush),
    .bubble_i           (id_bubble),
    .if2_valid_i        (id_if2_valid),
    .if2_pc_i           (id_if2_pc),
    .if2_inst_i         (id_if2_inst),
    .if2_pred_taken_i   (id_if2_pred_taken),
    .if2_pred_target_i  (id_if2_pred_target),
    .if2_fetch_fault_i  (id_if2_fetch_fault),
    .rf_rs1_addr_o      (rf_rs1_addr),
    .rf_rs2_addr_o      (rf_rs2_addr),
    .rf_rs1_data_i      (rf_rs1_data),
    .rf_rs2_data_i      (rf_rs2_data),
    .exe_valid_i        (idex_valid),
    .exe_rd_i           (idex_rd),
    .exe_reg_write_i    (idex_reg_write),
    .exe_mem_read_i     (idex_mem_read),
    .mem_valid_i        (exe_mem_valid),
    .mem_rd_i           (exe_mem_rd),
    .mem_reg_write_i    (exe_mem_reg_write),
    .load_use_stall_o   (load_use_stall_o),
    .idex_valid_o       (idex_valid),
    .idex_pc_o          (idex_pc),
    .idex_rd_o          (idex_rd),
    .idex_rs1_addr_o    (idex_rs1_addr),
    .idex_rs2_addr_o    (idex_rs2_addr),
    .idex_rs1_data_o    (idex_rs1_data),
    .idex_rs2_data_o    (idex_rs2_data),
    .idex_inst_o        (idex_inst),
    .idex_imm_o         (idex_imm),
    .idex_alu_op_o      (idex_alu_op),
    .idex_alu_src_imm_o (idex_alu_src_imm),
    .idex_mem_read_o    (idex_mem_read),
    .idex_mem_write_o   (idex_mem_write),
    .idex_mem_size_o    (idex_mem_size),
    .idex_load_sign_ext_o(idex_load_sign_ext),
    .idex_reg_write_o   (idex_reg_write),
    .idex_branch_type_o (idex_branch_type),
    .idex_is_jal_o      (idex_is_jal),
    .idex_is_jalr_o     (idex_is_jalr),
    .idex_is_lui_o      (idex_is_lui),
    .idex_is_lpc_o      (idex_is_lpc),
    .idex_is_halt_o     (idex_is_halt),
    .idex_pred_taken_o  (idex_pred_taken),
    .idex_pred_target_o (idex_pred_target),
    .idex_fetch_fault_o (idex_fetch_fault),
    .idex_fwd_rs1_sel_o (idex_fwd_rs1_sel),
    .idex_fwd_rs2_sel_o (idex_fwd_rs2_sel),
    .idex_illegal_o     (idex_illegal)
  );

  exe_stage u_exe (
    .clk                (clk),
    .rst                (rst),
    .stall_i            (exe_stall),
    .flush_i            (exe_flush),
    .id_valid_i         (idex_valid),
    .id_pc_i            (idex_pc),
    .id_rd_i            (idex_rd),
    .id_rs1_addr_i      (idex_rs1_addr),
    .id_rs2_addr_i      (idex_rs2_addr),
    .id_rs1_data_i      (idex_rs1_data),
    .id_rs2_data_i      (idex_rs2_data),
    .id_imm_i           (idex_imm),
    .id_alu_op_i        (idex_alu_op),
    .id_alu_src_imm_i   (idex_alu_src_imm),
    .id_reg_write_i     (idex_reg_write),
    .id_mem_read_i      (idex_mem_read),
    .id_mem_write_i     (idex_mem_write),
    .id_mem_size_i      (idex_mem_size),
    .id_load_sign_ext_i (idex_load_sign_ext),
    .id_branch_type_i   (idex_branch_type),
    .id_is_jal_i        (idex_is_jal),
    .id_is_jalr_i       (idex_is_jalr),
    .id_is_lui_i        (idex_is_lui),
    .id_is_lpc_i        (idex_is_lpc),
    .id_is_halt_i       (idex_is_halt),
    .id_pred_taken_i    (idex_pred_taken),
    .id_pred_target_i   (idex_pred_target),
    .id_fetch_fault_i   (idex_fetch_fault),
    .id_illegal_i       (idex_illegal),
    .id_fwd_rs1_sel_i   (idex_fwd_rs1_sel),
    .id_fwd_rs2_sel_i   (idex_fwd_rs2_sel),
    .mem_fwd_data_i     (exe_mem_result),
    .wb_fwd_data_i      (memwb_data),
    .redirect_valid_o   (redirect_valid),
    .redirect_pc_o      (redirect_pc),
    .mispredict_o       (mispredict),
    .mem_valid_o        (exe_mem_valid),
    .mem_rd_o           (exe_mem_rd),
    .mem_store_rs2_addr_o(exe_mem_store_rs2_addr),
    .mem_reg_write_o    (exe_mem_reg_write),
    .mem_mem_read_o     (exe_mem_mem_read),
    .mem_mem_write_o    (exe_mem_mem_write),
    .mem_mem_size_o     (exe_mem_mem_size),
    .mem_load_sign_ext_o(exe_mem_load_sign_ext),
    .mem_result_o       (exe_mem_result),
    .mem_store_data_o   (exe_mem_store_data),
    .mem_fetch_fault_o  (exe_mem_fetch_fault),
    .mem_illegal_o      (exe_mem_illegal),
    .mem_is_halt_o      (exe_mem_is_halt)
  );

  mem_stage u_mem (
    .clk                (clk),
    .rst                (rst),
    .stall_i            (mem_stall),
    .flush_i            (mem_flush),
    .exe_valid_i        (exe_mem_valid),
    .exe_rd_i           (exe_mem_rd),
    .exe_store_rs2_addr_i(exe_mem_store_rs2_addr),
    .exe_reg_write_i    (exe_mem_reg_write),
    .exe_mem_read_i     (exe_mem_mem_read),
    .exe_mem_write_i    (exe_mem_mem_write),
    .exe_mem_size_i     (exe_mem_mem_size),
    .exe_load_sign_ext_i(exe_mem_load_sign_ext),
    .exe_result_i       (exe_mem_result),
    .exe_store_data_i   (exe_mem_store_data),
    .exe_fetch_fault_i  (exe_mem_fetch_fault),
    .exe_illegal_i      (exe_mem_illegal),
    .exe_is_halt_i      (exe_mem_is_halt),
    .wb_fwd_valid_i     (rf_we),
    .wb_fwd_rd_i        (rf_waddr),
    .wb_fwd_data_i      (rf_wdata),
    .d_done_i           (d_done_i),
    .d_rdata_i          (d_rdata_i),
    .d_err_i            (d_err_i),
    .d_req_o            (d_req_o),
    .d_we_o             (d_we_o),
    .d_size_o           (d_size_o),
    .d_addr_o           (d_addr_o),
    .d_wdata_o          (d_wdata_o),
    .stall_req_o        (mem_stall_req),
    .memwb_valid_o      (memwb_valid),
    .memwb_rd_o         (memwb_rd),
    .memwb_reg_write_o  (memwb_reg_write),
    .memwb_data_o       (memwb_data),
    .memwb_mem_fault_o  (memwb_mem_fault),
    .memwb_fetch_fault_o(memwb_fetch_fault),
    .memwb_illegal_o    (memwb_illegal),
    .memwb_is_halt_o    (memwb_is_halt)
  );

  wb_stage u_wb (
    .memwb_valid_i      (memwb_valid),
    .memwb_rd_i         (memwb_rd),
    .memwb_reg_write_i  (memwb_reg_write),
    .memwb_data_i       (memwb_data),
    .memwb_mem_fault_i  (memwb_mem_fault),
    .memwb_fetch_fault_i(memwb_fetch_fault),
    .memwb_illegal_i    (memwb_illegal),
    .memwb_is_halt_i    (memwb_is_halt),
    .rf_we_o            (rf_we),
    .rf_waddr_o         (rf_waddr),
    .rf_wdata_o         (rf_wdata),
    .wb_valid_o         (wb_valid),
    .wb_fault_o         (wb_fault),
    .halted_o           (wb_halted_pulse)
  );

  regfile u_regfile (
    .clk                (clk),
    .rst                (rst),
    .rs1_addr_i         (rf_rs1_addr),
    .rs2_addr_i         (rf_rs2_addr),
    .rs1_data_o         (rf_rs1_data),
    .rs2_data_o         (rf_rs2_data),
    .we_i               (rf_we),
    .waddr_i            (rf_waddr),
    .wdata_i            (rf_wdata),
    .dbg_raddr_i        (dbg_gpr_addr_i),
    .dbg_rdata_o        (dbg_gpr_rdata),
    .dbg_we_i           (dbg_gpr_we),
    .dbg_waddr_i        (dbg_gpr_addr_i),
    .dbg_wdata_i        (dbg_gpr_wdata_i)
  );

  // ============================================================================
  // Status and profiling
  // ============================================================================

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

      if (wb_valid) begin
        retire_count <= retire_count + 32'd1;
      end
      if (redirect_valid) begin
        branch_redirect_count <= branch_redirect_count + 32'd1;
      end
      if (load_use_stall) begin
        load_stall_count <= load_stall_count + 32'd1;
      end
      if (mem_wait_stall) begin
        mem_stall_count <= mem_stall_count + 32'd1;
      end
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
  assign mem_wait_stall_o = mem_wait_stall;
  assign mispredict_o = mispredict;

  assign cycle_count_o = cycle_count;
  assign retire_count_o = retire_count;
  assign branch_redirect_count_o = branch_redirect_count;
  assign load_stall_count_o = load_stall_count;
  assign mem_stall_count_o = mem_stall_count;

  logic unused_biu_busy;
  assign unused_biu_busy = i_busy_i ^ d_busy_i;
endmodule : neocorefx_core
