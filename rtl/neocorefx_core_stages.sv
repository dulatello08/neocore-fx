//
// neocorefx_core_stages.sv
// NeoCoreFX - stage and regfile integration wrapper
//

module neocorefx_core_stages
  import core_pkg::*;
(
    input  logic        clk,
    input  logic        rst,

    input  logic        if1_stall_i,
    input  logic        if2_stall_i,
    input  logic        if2_flush_i,
    input  logic        id_stall_i,
    input  logic        id_flush_i,
    input  logic        id_bubble_i,
    input  logic        exe_stall_i,
    input  logic        exe_flush_i,
    input  logic        mem_stall_i,
    input  logic        mem_flush_i,

    input  logic        if1_redirect_valid_i,
    input  logic [31:0] if1_redirect_pc_i,

    input  logic        bp_update_valid_i,
    input  logic [31:0] bp_update_pc_i,
    input  logic        bp_update_taken_i,
    input  logic        ras_push_valid_i,
    input  logic [31:0] ras_push_addr_i,
    input  logic        ras_pop_valid_i,

    output logic        i_req_o,
    output logic [31:0] i_addr_o,
    input  logic        i_done_i,
    input  logic [31:0] i_rdata_i,
    input  logic        i_err_i,

    output logic        d_req_o,
    output logic        d_we_o,
    output logic [1:0]  d_size_o,
    output logic [31:0] d_addr_o,
    output logic [31:0] d_wdata_o,
    input  logic        d_done_i,
    input  logic [31:0] d_rdata_i,
    input  logic        d_err_i,

    output logic [3:0]  rf_rs1_addr_o,
    output logic [3:0]  rf_rs2_addr_o,
    input  logic [31:0] rf_rs1_data_i,
    input  logic [31:0] rf_rs2_data_i,
    output logic        rf_we_o,
    output logic [3:0]  rf_waddr_o,
    output logic [31:0] rf_wdata_o,

    output logic [31:0] if1_pc_o,
    output logic        load_use_stall_o,
    output logic        mem_stall_req_o,
    output logic        redirect_valid_o,
    output logic [31:0] redirect_pc_o,
    output logic        mispredict_o,

    output logic        idex_valid_o,
    output logic [31:0] idex_pc_o,
    output logic [3:0]  idex_rd_o,
    output logic [3:0]  idex_rs1_addr_o,
    output logic [31:0] idex_imm_o,
    output logic        idex_pred_taken_o,
    output logic [2:0]  idex_branch_type_o,
    output logic        idex_is_jal_o,
    output logic        idex_is_jalr_o,
    output logic [31:0] idex_inst_o,
    output logic        idex_illegal_o,

    output logic        wb_valid_o,
    output logic        wb_fault_o,
    output logic        wb_halted_pulse_o
);
    logic        if2_if1_valid;
    logic [31:0] if2_if1_pc;
    logic        if2_if1_pred_taken;

    logic        pred_valid;
    logic        pred_taken;
    logic [31:0] pred_target;

    logic        id_if2_valid;
    logic [31:0] id_if2_pc;
    logic [31:0] id_if2_inst;
    logic        id_if2_pred_taken;
    logic [31:0] id_if2_pred_target;
    logic        id_if2_fetch_fault;

    logic [3:0]  idex_rs2_addr;
    logic [31:0] idex_rs1_data;
    logic [31:0] idex_rs2_data;
    logic [4:0]  idex_alu_op;
    logic        idex_alu_src_imm;
    logic        idex_mem_read;
    logic        idex_mem_write;
    logic [1:0]  idex_mem_size;
    logic        idex_load_sign_ext;
    logic        idex_reg_write;
    logic        idex_is_lui;
    logic        idex_is_lpc;
    logic        idex_is_halt;
    logic [31:0] idex_pred_target;
    logic        idex_fetch_fault;
    logic [1:0]  idex_fwd_rs1_sel;
    logic [1:0]  idex_fwd_rs2_sel;

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

    logic        memwb_valid;
    logic [3:0]  memwb_rd;
    logic        memwb_reg_write;
    logic [31:0] memwb_data;
    logic        memwb_mem_fault;
    logic        memwb_fetch_fault;
    logic        memwb_illegal;
    logic        memwb_is_halt;

    if1_stage u_if1 (
        .clk                (clk),
        .rst                (rst),
        .stall_i            (if1_stall_i),
        .redirect_valid_i   (if1_redirect_valid_i),
        .redirect_pc_i      (if1_redirect_pc_i),
        .pred_valid_i       (pred_valid),
        .pred_taken_i       (pred_taken),
        .pred_target_i      (pred_target),
        .i_req_o            (i_req_o),
        .i_addr_o           (i_addr_o),
        .if2_valid_o        (if2_if1_valid),
        .if2_pc_o           (if2_if1_pc),
        .if2_pred_taken_o   (if2_if1_pred_taken),
        .pc_o               (if1_pc_o)
    );

    if2_stage u_if2 (
        .clk                (clk),
        .rst                (rst),
        .stall_i            (if2_stall_i),
        .flush_i            (if2_flush_i),
        .if1_valid_i        (if2_if1_valid),
        .if1_pc_i           (if2_if1_pc),
        .if1_pred_taken_i   (if2_if1_pred_taken),
        .bp_update_valid_i  (bp_update_valid_i),
        .bp_update_pc_i     (bp_update_pc_i),
        .bp_update_taken_i  (bp_update_taken_i),
        .ras_push_valid_i   (ras_push_valid_i),
        .ras_push_addr_i    (ras_push_addr_i),
        .ras_pop_valid_i    (ras_pop_valid_i),
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
        .stall_i            (id_stall_i),
        .flush_i            (id_flush_i),
        .bubble_i           (id_bubble_i),
        .if2_valid_i        (id_if2_valid),
        .if2_pc_i           (id_if2_pc),
        .if2_inst_i         (id_if2_inst),
        .if2_pred_taken_i   (id_if2_pred_taken),
        .if2_pred_target_i  (id_if2_pred_target),
        .if2_fetch_fault_i  (id_if2_fetch_fault),
        .rf_rs1_addr_o      (rf_rs1_addr_o),
        .rf_rs2_addr_o      (rf_rs2_addr_o),
        .rf_rs1_data_i      (rf_rs1_data_i),
        .rf_rs2_data_i      (rf_rs2_data_i),
        .exe_valid_i        (idex_valid_o),
        .exe_rd_i           (idex_rd_o),
        .exe_reg_write_i    (idex_reg_write),
        .exe_mem_read_i     (idex_mem_read),
        .mem_valid_i        (exe_mem_valid),
        .mem_rd_i           (exe_mem_rd),
        .mem_reg_write_i    (exe_mem_reg_write),
        .load_use_stall_o   (load_use_stall_o),
        .idex_valid_o       (idex_valid_o),
        .idex_pc_o          (idex_pc_o),
        .idex_rd_o          (idex_rd_o),
        .idex_rs1_addr_o    (idex_rs1_addr_o),
        .idex_rs2_addr_o    (idex_rs2_addr),
        .idex_rs1_data_o    (idex_rs1_data),
        .idex_rs2_data_o    (idex_rs2_data),
        .idex_inst_o        (idex_inst_o),
        .idex_imm_o         (idex_imm_o),
        .idex_alu_op_o      (idex_alu_op),
        .idex_alu_src_imm_o (idex_alu_src_imm),
        .idex_mem_read_o    (idex_mem_read),
        .idex_mem_write_o   (idex_mem_write),
        .idex_mem_size_o    (idex_mem_size),
        .idex_load_sign_ext_o(idex_load_sign_ext),
        .idex_reg_write_o   (idex_reg_write),
        .idex_branch_type_o (idex_branch_type_o),
        .idex_is_jal_o      (idex_is_jal_o),
        .idex_is_jalr_o     (idex_is_jalr_o),
        .idex_is_lui_o      (idex_is_lui),
        .idex_is_lpc_o      (idex_is_lpc),
        .idex_is_halt_o     (idex_is_halt),
        .idex_pred_taken_o  (idex_pred_taken_o),
        .idex_pred_target_o (idex_pred_target),
        .idex_fetch_fault_o (idex_fetch_fault),
        .idex_fwd_rs1_sel_o (idex_fwd_rs1_sel),
        .idex_fwd_rs2_sel_o (idex_fwd_rs2_sel),
        .idex_illegal_o     (idex_illegal_o)
    );

    exe_stage u_exe (
        .clk                (clk),
        .rst                (rst),
        .stall_i            (exe_stall_i),
        .flush_i            (exe_flush_i),
        .id_valid_i         (idex_valid_o),
        .id_pc_i            (idex_pc_o),
        .id_rd_i            (idex_rd_o),
        .id_rs1_addr_i      (idex_rs1_addr_o),
        .id_rs2_addr_i      (idex_rs2_addr),
        .id_rs1_data_i      (idex_rs1_data),
        .id_rs2_data_i      (idex_rs2_data),
        .id_imm_i           (idex_imm_o),
        .id_alu_op_i        (idex_alu_op),
        .id_alu_src_imm_i   (idex_alu_src_imm),
        .id_reg_write_i     (idex_reg_write),
        .id_mem_read_i      (idex_mem_read),
        .id_mem_write_i     (idex_mem_write),
        .id_mem_size_i      (idex_mem_size),
        .id_load_sign_ext_i (idex_load_sign_ext),
        .id_branch_type_i   (idex_branch_type_o),
        .id_is_jal_i        (idex_is_jal_o),
        .id_is_jalr_i       (idex_is_jalr_o),
        .id_is_lui_i        (idex_is_lui),
        .id_is_lpc_i        (idex_is_lpc),
        .id_is_halt_i       (idex_is_halt),
        .id_pred_taken_i    (idex_pred_taken_o),
        .id_pred_target_i   (idex_pred_target),
        .id_fetch_fault_i   (idex_fetch_fault),
        .id_illegal_i       (idex_illegal_o),
        .id_fwd_rs1_sel_i   (idex_fwd_rs1_sel),
        .id_fwd_rs2_sel_i   (idex_fwd_rs2_sel),
        .mem_fwd_data_i     (exe_mem_result),
        .wb_fwd_data_i      (memwb_data),
        .redirect_valid_o   (redirect_valid_o),
        .redirect_pc_o      (redirect_pc_o),
        .mispredict_o       (mispredict_o),
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
        .stall_i            (mem_stall_i),
        .flush_i            (mem_flush_i),
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
        .wb_fwd_valid_i     (rf_we_o),
        .wb_fwd_rd_i        (rf_waddr_o),
        .wb_fwd_data_i      (rf_wdata_o),
        .d_done_i           (d_done_i),
        .d_rdata_i          (d_rdata_i),
        .d_err_i            (d_err_i),
        .d_req_o            (d_req_o),
        .d_we_o             (d_we_o),
        .d_size_o           (d_size_o),
        .d_addr_o           (d_addr_o),
        .d_wdata_o          (d_wdata_o),
        .stall_req_o        (mem_stall_req_o),
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
        .rf_we_o            (rf_we_o),
        .rf_waddr_o         (rf_waddr_o),
        .rf_wdata_o         (rf_wdata_o),
        .wb_valid_o         (wb_valid_o),
        .wb_fault_o         (wb_fault_o),
        .halted_o           (wb_halted_pulse_o)
    );
endmodule
