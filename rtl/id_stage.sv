//
// id_stage.sv
// NeoCoreFX - ID wrapper (decode + hazards + ID/EX pipeline register)
//

module id_stage
  import core_pkg::*;
(
    input  logic        clk,
    input  logic        rst,
    input  logic        stall_i,
    input  logic        flush_i,
    input  logic        bubble_i,

    input  logic        if2_valid_i,
    input  logic [31:0] if2_pc_i,
    input  logic [31:0] if2_inst_i,
    input  logic        if2_pred_taken_i,
    input  logic [31:0] if2_pred_target_i,
    input  logic        if2_fetch_fault_i,

    output logic [3:0]  rf_rs1_addr_o,
    output logic [3:0]  rf_rs2_addr_o,
    input  logic [31:0] rf_rs1_data_i,
    input  logic [31:0] rf_rs2_data_i,

    input  logic        exe_valid_i,
    input  logic [3:0]  exe_rd_i,
    input  logic        exe_reg_write_i,
    input  logic        exe_mem_read_i,

    input  logic        mem_valid_i,
    input  logic [3:0]  mem_rd_i,
    input  logic        mem_reg_write_i,

    output logic        load_use_stall_o,

    output logic        idex_valid_o,
    output logic [31:0] idex_pc_o,
    output logic [3:0]  idex_rd_o,
    output logic [3:0]  idex_rs1_addr_o,
    output logic [3:0]  idex_rs2_addr_o,
    output logic [31:0] idex_rs1_data_o,
    output logic [31:0] idex_rs2_data_o,
    output logic [31:0] idex_inst_o,
    output logic [31:0] idex_imm_o,
    output logic [4:0]  idex_alu_op_o,
    output logic        idex_alu_src_imm_o,
    output logic        idex_mem_read_o,
    output logic        idex_mem_write_o,
    output logic [1:0]  idex_mem_size_o,
    output logic        idex_load_sign_ext_o,
    output logic        idex_reg_write_o,
    output logic [2:0]  idex_branch_type_o,
    output logic        idex_is_jal_o,
    output logic        idex_is_jalr_o,
    output logic        idex_is_lui_o,
    output logic        idex_is_lpc_o,
    output logic        idex_is_halt_o,
    output logic        idex_pred_taken_o,
    output logic [31:0] idex_pred_target_o,
    output logic        idex_fetch_fault_o,
    output logic [1:0]  idex_fwd_rs1_sel_o,
    output logic [1:0]  idex_fwd_rs2_sel_o,
    output logic        idex_illegal_o
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [3:0]  rd_d;
    logic [3:0]  rs1_d;
    logic [3:0]  rs2_d;
    logic        rs1_used_d;
    logic        rs2_used_d;
    logic [31:0] imm_d;
    alu_op_t     alu_op_d;
    branch_t     branch_type_d;
    logic        alu_src_imm_d;
    logic        mem_read_d;
    logic        mem_write_d;
    mem_size_t   mem_size_d;
    logic        load_sign_ext_d;
    logic        reg_write_d;
    logic        is_jal_d;
    logic        is_jalr_d;
    logic        is_lui_d;
    logic        is_lpc_d;
    logic        is_halt_d;
    logic        illegal_d;
    fwd_sel_t    fwd_rs1_sel_d;
    fwd_sel_t    fwd_rs2_sel_d;

    id_stage_decode u_decode (
        .if2_inst_i       (if2_inst_i),
        .rf_rs1_addr_o    (rf_rs1_addr_o),
        .rf_rs2_addr_o    (rf_rs2_addr_o),
        .rd_o             (rd_d),
        .rs1_o            (rs1_d),
        .rs2_o            (rs2_d),
        .rs1_used_o       (rs1_used_d),
        .rs2_used_o       (rs2_used_d),
        .imm_o            (imm_d),
        .alu_op_o         (alu_op_d),
        .branch_type_o    (branch_type_d),
        .alu_src_imm_o    (alu_src_imm_d),
        .mem_read_o       (mem_read_d),
        .mem_write_o      (mem_write_d),
        .mem_size_o       (mem_size_d),
        .load_sign_ext_o  (load_sign_ext_d),
        .reg_write_o      (reg_write_d),
        .is_jal_o         (is_jal_d),
        .is_jalr_o        (is_jalr_d),
        .is_lui_o         (is_lui_d),
        .is_lpc_o         (is_lpc_d),
        .is_halt_o        (is_halt_d),
        .illegal_o        (illegal_d)
    );

    id_stage_hazards u_hazards (
        .illegal_i        (illegal_d),
        .if2_valid_i      (if2_valid_i),
        .rs1_i            (rs1_d),
        .rs2_i            (rs2_d),
        .rs1_used_i       (rs1_used_d),
        .rs2_used_i       (rs2_used_d),
        .mem_write_i      (mem_write_d),
        .exe_valid_i      (exe_valid_i),
        .exe_rd_i         (exe_rd_i),
        .exe_reg_write_i  (exe_reg_write_i),
        .exe_mem_read_i   (exe_mem_read_i),
        .mem_valid_i      (mem_valid_i),
        .mem_rd_i         (mem_rd_i),
        .mem_reg_write_i  (mem_reg_write_i),
        .load_use_stall_o (load_use_stall_o),
        .fwd_rs1_sel_o    (fwd_rs1_sel_d),
        .fwd_rs2_sel_o    (fwd_rs2_sel_d)
    );

    id_stage_pipe_reg u_pipe_reg (
        .clk                (clk),
        .rst                (rst),
        .stall_i            (stall_i),
        .flush_i            (flush_i),
        .bubble_i           (bubble_i),
        .if2_valid_i        (if2_valid_i),
        .if2_pc_i           (if2_pc_i),
        .if2_inst_i         (if2_inst_i),
        .if2_pred_taken_i   (if2_pred_taken_i),
        .if2_pred_target_i  (if2_pred_target_i),
        .if2_fetch_fault_i  (if2_fetch_fault_i),
        .rd_i               (rd_d),
        .rs1_i              (rs1_d),
        .rs2_i              (rs2_d),
        .rf_rs1_data_i      (rf_rs1_data_i),
        .rf_rs2_data_i      (rf_rs2_data_i),
        .imm_i              (imm_d),
        .alu_op_i           (alu_op_d),
        .alu_src_imm_i      (alu_src_imm_d),
        .mem_read_i         (mem_read_d),
        .mem_write_i        (mem_write_d),
        .mem_size_i         (mem_size_d),
        .load_sign_ext_i    (load_sign_ext_d),
        .reg_write_i        (reg_write_d),
        .branch_type_i      (branch_type_d),
        .is_jal_i           (is_jal_d),
        .is_jalr_i          (is_jalr_d),
        .is_lui_i           (is_lui_d),
        .is_lpc_i           (is_lpc_d),
        .is_halt_i          (is_halt_d),
        .illegal_i          (illegal_d),
        .fwd_rs1_sel_i      (fwd_rs1_sel_d),
        .fwd_rs2_sel_i      (fwd_rs2_sel_d),
        .idex_valid_o       (idex_valid_o),
        .idex_pc_o          (idex_pc_o),
        .idex_rd_o          (idex_rd_o),
        .idex_rs1_addr_o    (idex_rs1_addr_o),
        .idex_rs2_addr_o    (idex_rs2_addr_o),
        .idex_rs1_data_o    (idex_rs1_data_o),
        .idex_rs2_data_o    (idex_rs2_data_o),
        .idex_inst_o        (idex_inst_o),
        .idex_imm_o         (idex_imm_o),
        .idex_alu_op_o      (idex_alu_op_o),
        .idex_alu_src_imm_o (idex_alu_src_imm_o),
        .idex_mem_read_o    (idex_mem_read_o),
        .idex_mem_write_o   (idex_mem_write_o),
        .idex_mem_size_o    (idex_mem_size_o),
        .idex_load_sign_ext_o(idex_load_sign_ext_o),
        .idex_reg_write_o   (idex_reg_write_o),
        .idex_branch_type_o (idex_branch_type_o),
        .idex_is_jal_o      (idex_is_jal_o),
        .idex_is_jalr_o     (idex_is_jalr_o),
        .idex_is_lui_o      (idex_is_lui_o),
        .idex_is_lpc_o      (idex_is_lpc_o),
        .idex_is_halt_o     (idex_is_halt_o),
        .idex_pred_taken_o  (idex_pred_taken_o),
        .idex_pred_target_o (idex_pred_target_o),
        .idex_fetch_fault_o (idex_fetch_fault_o),
        .idex_fwd_rs1_sel_o (idex_fwd_rs1_sel_o),
        .idex_fwd_rs2_sel_o (idex_fwd_rs2_sel_o),
        .idex_illegal_o     (idex_illegal_o)
    );
endmodule
