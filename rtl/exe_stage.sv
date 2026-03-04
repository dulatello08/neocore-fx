//
// exe_stage.sv
// NeoCoreFX - EXE (forward mux + ALU + branch/jump resolution + halt propagation)
//

module exe_stage
  import core_pkg::*;
(
    // Clock/reset and pipeline control.
    input  logic        clk,
    input  logic        rst,
    input  logic        stall_i,
    input  logic        flush_i,

    // ID -> EXE pipeline inputs.
    input  logic        id_valid_i,
    input  logic [31:0] id_pc_i,
    input  logic [3:0]  id_rd_i,
    input  logic [3:0]  id_rs1_addr_i,
    input  logic [3:0]  id_rs2_addr_i,
    input  logic [31:0] id_rs1_data_i,
    input  logic [31:0] id_rs2_data_i,
    input  logic [31:0] id_imm_i,
    input  logic [4:0]  id_alu_op_i,
    input  logic        id_alu_src_imm_i,
    input  logic        id_reg_write_i,
    input  logic        id_mem_read_i,
    input  logic        id_mem_write_i,
    input  logic [1:0]  id_mem_size_i,
    input  logic        id_load_sign_ext_i,
    input  logic [2:0]  id_branch_type_i,
    input  logic        id_is_jal_i,
    input  logic        id_is_jalr_i,
    input  logic        id_is_lui_i,
    input  logic        id_is_lpc_i,
    // Halt metadata from decode (`B .` alias).
    input  logic        id_is_halt_i,
    input  logic        id_pred_taken_i,
    input  logic        id_fetch_fault_i,
    input  logic        id_illegal_i,
    input  logic [1:0]  id_fwd_rs1_sel_i,
    input  logic [1:0]  id_fwd_rs2_sel_i,

    // Forwarded data sources.
    input  logic [31:0] mem_fwd_data_i,
    input  logic [31:0] wb_fwd_data_i,

    // Redirect / branch resolution outputs.
    output logic        redirect_valid_o,
    output logic [31:0] redirect_pc_o,
    output logic        mispredict_o,

    // EXE -> MEM pipeline outputs.
    output logic        mem_valid_o,
    output logic [3:0]  mem_rd_o,
    output logic [3:0]  mem_store_rs2_addr_o,
    output logic        mem_reg_write_o,
    output logic        mem_mem_read_o,
    output logic        mem_mem_write_o,
    output logic [1:0]  mem_mem_size_o,
    output logic        mem_load_sign_ext_o,
    output logic [31:0] mem_result_o,
    output logic [31:0] mem_store_data_o,
    output logic        mem_fetch_fault_o,
    output logic        mem_illegal_o,
    // Halt metadata toward MEM stage.
    output logic        mem_is_halt_o
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [31:0] rs1_final;
    logic [31:0] rs2_final;
    logic [31:0] alu_rhs;
    logic [31:0] alu_result;
    logic [31:0] core_result;
    logic [31:0] mem_addr;

    logic [31:0] branch_target;
    logic [31:0] jal_target;
    logic [31:0] jalr_target;
    logic [31:0] actual_target;
    logic [31:0] fallthrough_pc;

    logic branch_taken;
    logic actual_taken;

    logic [63:0] mul_uu;
    logic signed [63:0] mul_ss;
    logic signed [63:0] mul_su;

    always_comb begin
        rs1_final = id_rs1_data_i;
        case (id_fwd_rs1_sel_i)
            FWD_MEM: rs1_final = mem_fwd_data_i;
            FWD_WB:  rs1_final = wb_fwd_data_i;
            default:      rs1_final = id_rs1_data_i;
        endcase

        rs2_final = id_rs2_data_i;
        case (id_fwd_rs2_sel_i)
            FWD_MEM: rs2_final = mem_fwd_data_i;
            FWD_WB:  rs2_final = wb_fwd_data_i;
            default:      rs2_final = id_rs2_data_i;
        endcase
    end

    assign alu_rhs = id_alu_src_imm_i ? id_imm_i : rs2_final;

    assign mul_uu = rs1_final * rs2_final;
    assign mul_ss = $signed(rs1_final) * $signed(rs2_final);
    assign mul_su = $signed(rs1_final) * $signed({1'b0, rs2_final});

    always_comb begin
        case (id_alu_op_i)
            ALU_ADD:    alu_result = rs1_final + alu_rhs;
            ALU_SUB:    alu_result = rs1_final - alu_rhs;
            ALU_AND:    alu_result = rs1_final & alu_rhs;
            ALU_OR:     alu_result = rs1_final | alu_rhs;
            ALU_XOR:    alu_result = rs1_final ^ alu_rhs;
            ALU_SLT:    alu_result = ($signed(rs1_final) < $signed(alu_rhs)) ? 32'd1 : 32'd0;
            ALU_SLTU:   alu_result = (rs1_final < alu_rhs) ? 32'd1 : 32'd0;
            ALU_SLL:    alu_result = rs1_final << alu_rhs[4:0];
            ALU_SRL:    alu_result = rs1_final >> alu_rhs[4:0];
            ALU_SRA:    alu_result = $signed(rs1_final) >>> alu_rhs[4:0];
            ALU_MUL:    alu_result = mul_uu[31:0];
            ALU_MULH:   alu_result = mul_ss[63:32];
            ALU_MULHU:  alu_result = mul_uu[63:32];
            ALU_MULHSU: alu_result = mul_su[63:32];
            default:         alu_result = rs1_final;
        endcase
    end

    always_comb begin
        branch_taken = 1'b0;
        case (id_branch_type_i)
            BR_UNCOND: branch_taken = 1'b1;
            BR_EQ:     branch_taken = (rs1_final == rs2_final);
            BR_NE:     branch_taken = (rs1_final != rs2_final);
            BR_LT:     branch_taken = ($signed(rs1_final) < $signed(rs2_final));
            BR_LTU:    branch_taken = (rs1_final < rs2_final);
            default:        branch_taken = 1'b0;
        endcase
    end

    assign branch_target = id_pc_i + id_imm_i;
    assign jal_target = id_pc_i + id_imm_i;
    assign jalr_target = (rs1_final + id_imm_i) & 32'hFFFF_FFFC;
    assign fallthrough_pc = id_pc_i + 32'd4;

    assign actual_taken = id_is_jal_i
                       || id_is_jalr_i
                       || ((id_branch_type_i != BR_NONE) && branch_taken);

    always_comb begin
        if (id_is_jalr_i) begin
            actual_target = jalr_target;
        end else if (id_is_jal_i) begin
            actual_target = jal_target;
        end else if ((id_branch_type_i != BR_NONE) && branch_taken) begin
            actual_target = branch_target;
        end else begin
            actual_target = fallthrough_pc;
        end
    end

    always_comb begin
        redirect_valid_o = 1'b0;
        redirect_pc_o = actual_target;
        mispredict_o = 1'b0;

        if (id_valid_i && !id_illegal_i) begin
            if (id_is_jalr_i) begin
                redirect_valid_o = 1'b1;
                mispredict_o = 1'b1;
            end else if (id_is_jal_i || (id_branch_type_i != BR_NONE)) begin
                if (actual_taken != id_pred_taken_i) begin
                    redirect_valid_o = 1'b1;
                    mispredict_o = 1'b1;
                    if (!actual_taken) begin
                        redirect_pc_o = fallthrough_pc;
                    end
                end
            end
        end
    end

    always_comb begin
        core_result = alu_result;
        if (id_is_lui_i) begin
            core_result = {id_imm_i[15:0], 16'h0000};
        end else if (id_is_lpc_i) begin
            core_result = id_pc_i + id_imm_i;
        end else if (id_is_jal_i || id_is_jalr_i) begin
            core_result = fallthrough_pc;
        end
    end

    assign mem_addr = rs1_final + id_imm_i;

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_valid_o          <= 1'b0;
            mem_rd_o             <= 4'h0;
            mem_store_rs2_addr_o <= 4'h0;
            mem_reg_write_o      <= 1'b0;
            mem_mem_read_o       <= 1'b0;
            mem_mem_write_o      <= 1'b0;
            mem_mem_size_o       <= SIZE_WORD;
            mem_load_sign_ext_o  <= 1'b0;
            mem_result_o         <= 32'h0000_0000;
            mem_store_data_o     <= 32'h0000_0000;
            mem_fetch_fault_o    <= 1'b0;
            mem_illegal_o        <= 1'b0;
            mem_is_halt_o        <= 1'b0;
        end else if (flush_i) begin
            mem_valid_o          <= 1'b0;
            mem_rd_o             <= 4'h0;
            mem_store_rs2_addr_o <= 4'h0;
            mem_reg_write_o      <= 1'b0;
            mem_mem_read_o       <= 1'b0;
            mem_mem_write_o      <= 1'b0;
            mem_mem_size_o       <= SIZE_WORD;
            mem_load_sign_ext_o  <= 1'b0;
            mem_result_o         <= 32'h0000_0000;
            mem_store_data_o     <= 32'h0000_0000;
            mem_fetch_fault_o    <= 1'b0;
            mem_illegal_o        <= 1'b0;
            mem_is_halt_o        <= 1'b0;
        end else if (!stall_i) begin
            mem_valid_o          <= id_valid_i;
            mem_rd_o             <= id_rd_i;
            mem_store_rs2_addr_o <= id_rs2_addr_i;
            mem_reg_write_o      <= id_reg_write_i;
            mem_mem_read_o       <= id_mem_read_i;
            mem_mem_write_o      <= id_mem_write_i;
            mem_mem_size_o       <= id_mem_size_i;
            mem_load_sign_ext_o  <= id_load_sign_ext_i;
            mem_result_o         <= (id_mem_read_i || id_mem_write_i) ? mem_addr : core_result;
            mem_store_data_o     <= rs2_final;
            mem_fetch_fault_o    <= id_fetch_fault_i;
            mem_illegal_o        <= id_illegal_i;
            mem_is_halt_o        <= id_valid_i && id_is_halt_i && !id_illegal_i;
        end
    end
endmodule
