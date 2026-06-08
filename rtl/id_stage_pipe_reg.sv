//
// id_stage_pipe_reg.sv
// NeoCoreFX - ID/EXE pipeline register
//

module id_stage_pipe_reg
  import core_pkg::*;
(
    input  logic       clk,
    input  logic       rst,
    input  logic       stall_i,
    input  logic       flush_i,
    input  logic       bubble_i,

    input  logic       if2_valid_i,
    input  logic [31:0]if2_pc_i,
    input  logic [31:0]if2_inst_i,
    input  logic       if2_pred_taken_i,
    input  logic [31:0]if2_pred_target_i,
    input  logic       if2_fetch_fault_i,

    input  logic [3:0] rd_i,
    input  logic [3:0] rs1_i,
    input  logic [3:0] rs2_i,
    input  logic [31:0]rf_rs1_data_i,
    input  logic [31:0]rf_rs2_data_i,

    input  logic [31:0]imm_i,
    input  alu_op_t    alu_op_i,
    input  logic       alu_src_imm_i,
    input  logic       mem_read_i,
    input  logic       mem_write_i,
    input  mem_size_t  mem_size_i,
    input  logic       load_sign_ext_i,
    input  logic       reg_write_i,
    input  branch_t    branch_type_i,
    input  logic       is_jal_i,
    input  logic       is_jalr_i,
    input  logic       is_lui_i,
    input  logic       is_lpc_i,
    input  logic       is_halt_i,
    input  logic       illegal_i,
    input  fwd_sel_t   fwd_rs1_sel_i,
    input  fwd_sel_t   fwd_rs2_sel_i,

    output logic       idex_valid_o,
    output logic [31:0]idex_pc_o,
    output logic [3:0] idex_rd_o,
    output logic [3:0] idex_rs1_addr_o,
    output logic [3:0] idex_rs2_addr_o,
    output logic [31:0]idex_rs1_data_o,
    output logic [31:0]idex_rs2_data_o,
    output logic [31:0]idex_inst_o,
    output logic [31:0]idex_imm_o,
    output logic [4:0] idex_alu_op_o,
    output logic       idex_alu_src_imm_o,
    output logic       idex_mem_read_o,
    output logic       idex_mem_write_o,
    output logic [1:0] idex_mem_size_o,
    output logic       idex_load_sign_ext_o,
    output logic       idex_reg_write_o,
    output logic [2:0] idex_branch_type_o,
    output logic       idex_is_jal_o,
    output logic       idex_is_jalr_o,
    output logic       idex_is_lui_o,
    output logic       idex_is_lpc_o,
    output logic       idex_is_halt_o,
    output logic       idex_pred_taken_o,
    output logic [31:0]idex_pred_target_o,
    output logic       idex_fetch_fault_o,
    output logic [1:0] idex_fwd_rs1_sel_o,
    output logic [1:0] idex_fwd_rs2_sel_o,
    output logic       idex_illegal_o
);
    task automatic clear_reg;
        begin
            idex_valid_o         <= 1'b0;
            idex_pc_o            <= 32'h0000_0000;
            idex_rd_o            <= 4'h0;
            idex_rs1_addr_o      <= 4'h0;
            idex_rs2_addr_o      <= 4'h0;
            idex_rs1_data_o      <= 32'h0000_0000;
            idex_rs2_data_o      <= 32'h0000_0000;
            idex_inst_o          <= 32'h0000_0000;
            idex_imm_o           <= 32'h0000_0000;
            idex_alu_op_o        <= ALU_ADD;
            idex_alu_src_imm_o   <= 1'b0;
            idex_mem_read_o      <= 1'b0;
            idex_mem_write_o     <= 1'b0;
            idex_mem_size_o      <= SIZE_WORD;
            idex_load_sign_ext_o <= 1'b0;
            idex_reg_write_o     <= 1'b0;
            idex_branch_type_o   <= BR_NONE;
            idex_is_jal_o        <= 1'b0;
            idex_is_jalr_o       <= 1'b0;
            idex_is_lui_o        <= 1'b0;
            idex_is_lpc_o        <= 1'b0;
            idex_is_halt_o       <= 1'b0;
            idex_pred_taken_o    <= 1'b0;
            idex_pred_target_o   <= 32'h0000_0000;
            idex_fetch_fault_o   <= 1'b0;
            idex_fwd_rs1_sel_o   <= FWD_NONE;
            idex_fwd_rs2_sel_o   <= FWD_NONE;
            idex_illegal_o       <= 1'b0;
        end
    endtask

    always_ff @(posedge clk) begin
        if (rst) begin
            clear_reg();
        end else if (flush_i) begin
            clear_reg();
        end else if (!stall_i) begin
            if (bubble_i) begin
                clear_reg();
            end else begin
                idex_valid_o         <= if2_valid_i;
                idex_pc_o            <= if2_pc_i;
                idex_rd_o            <= rd_i;
                idex_rs1_addr_o      <= rs1_i;
                idex_rs2_addr_o      <= rs2_i;
                idex_rs1_data_o      <= rf_rs1_data_i;
                idex_rs2_data_o      <= rf_rs2_data_i;
                idex_inst_o          <= if2_inst_i;
                idex_imm_o           <= imm_i;
                idex_alu_op_o        <= alu_op_i;
                idex_alu_src_imm_o   <= alu_src_imm_i;
                idex_mem_read_o      <= mem_read_i && !illegal_i;
                idex_mem_write_o     <= mem_write_i && !illegal_i;
                idex_mem_size_o      <= mem_size_i;
                idex_load_sign_ext_o <= load_sign_ext_i;
                idex_reg_write_o     <= reg_write_i && !illegal_i;
                idex_branch_type_o   <= illegal_i ? BR_NONE : branch_type_i;
                idex_is_jal_o        <= is_jal_i && !illegal_i;
                idex_is_jalr_o       <= is_jalr_i && !illegal_i;
                idex_is_lui_o        <= is_lui_i && !illegal_i;
                idex_is_lpc_o        <= is_lpc_i && !illegal_i;
                idex_is_halt_o       <= is_halt_i && !illegal_i;
                idex_pred_taken_o    <= if2_pred_taken_i;
                idex_pred_target_o   <= if2_pred_target_i;
                idex_fetch_fault_o   <= if2_fetch_fault_i;
                idex_fwd_rs1_sel_o   <= fwd_rs1_sel_i;
                idex_fwd_rs2_sel_o   <= fwd_rs2_sel_i;
                idex_illegal_o       <= illegal_i;
            end
        end
    end
endmodule
