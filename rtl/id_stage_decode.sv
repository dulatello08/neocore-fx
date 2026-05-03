//
// id_stage_decode.sv
// NeoCoreFX - ID decode logic
//

module id_stage_decode
  import core_pkg::*;
(
    input  logic [31:0] if2_inst_i,

    output logic [3:0]  rf_rs1_addr_o,
    output logic [3:0]  rf_rs2_addr_o,
    output logic [3:0]  rd_o,
    output logic [3:0]  rs1_o,
    output logic [3:0]  rs2_o,

    output logic        rs1_used_o,
    output logic        rs2_used_o,
    output logic [31:0] imm_o,
    output alu_op_t     alu_op_o,
    output branch_t     branch_type_o,
    output logic        alu_src_imm_o,
    output logic        mem_read_o,
    output logic        mem_write_o,
    output mem_size_t   mem_size_o,
    output logic        load_sign_ext_o,
    output logic        reg_write_o,
    output logic        is_jal_o,
    output logic        is_jalr_o,
    output logic        is_lui_o,
    output logic        is_lpc_o,
    output logic        is_halt_o,
    output logic        illegal_o
);
    logic [3:0]  class_d;
    logic [3:0]  op_d;
    logic [3:0]  rs1_d;
    logic [3:0]  rs2_d;
    logic [11:0] ext12_d;
    logic [15:0] imm16_d;
    logic [15:0] imm16_split_d;
    logic [19:0] off20_d;

    assign class_d = if2_inst_i[31:28];
    assign op_d = if2_inst_i[27:24];
    assign rd_o = if2_inst_i[23:20];
    assign rs1_d = if2_inst_i[19:16];
    assign rs2_d = if2_inst_i[15:12];
    assign ext12_d = if2_inst_i[11:0];
    assign imm16_d = if2_inst_i[15:0];
    assign imm16_split_d = {if2_inst_i[23:20], if2_inst_i[11:0]};
    assign off20_d = if2_inst_i[19:0];

    assign rs1_o = rs1_d;
    assign rs2_o = rs2_d;

    always_comb begin
        rf_rs1_addr_o = rs1_d;
        rf_rs2_addr_o = rs2_d;

        rs1_used_o = 1'b0;
        rs2_used_o = 1'b0;
        imm_o = 32'h0000_0000;
        alu_op_o = ALU_ADD;
        branch_type_o = BR_NONE;
        alu_src_imm_o = 1'b0;
        mem_read_o = 1'b0;
        mem_write_o = 1'b0;
        mem_size_o = SIZE_WORD;
        load_sign_ext_o = 1'b0;
        reg_write_o = 1'b0;
        is_jal_o = 1'b0;
        is_jalr_o = 1'b0;
        is_lui_o = 1'b0;
        is_lpc_o = 1'b0;
        is_halt_o = 1'b0;
        illegal_o = 1'b0;

        if (if2_inst_i != 32'h0000_0000) begin
            case (class_d)
                4'h0: begin
                    rs1_used_o = 1'b1;
                    rs2_used_o = 1'b1;
                    reg_write_o = 1'b1;
                    if (ext12_d != 12'h000) begin
                        illegal_o = 1'b1;
                    end

                    case (op_d)
                        4'h1: alu_op_o = ALU_ADD;
                        4'h2: alu_op_o = ALU_SUB;
                        4'h3: alu_op_o = ALU_AND;
                        4'h4: alu_op_o = ALU_OR;
                        4'h5: alu_op_o = ALU_XOR;
                        4'h6: alu_op_o = ALU_SLT;
                        4'h7: alu_op_o = ALU_SLTU;
                        4'h8: alu_op_o = ALU_SLL;
                        4'h9: alu_op_o = ALU_SRL;
                        4'hA: alu_op_o = ALU_SRA;
                        4'hB: alu_op_o = ALU_MUL;
                        4'hC: alu_op_o = ALU_MULH;
                        4'hD: alu_op_o = ALU_MULHU;
                        4'hE: alu_op_o = ALU_MULHSU;
                        default: illegal_o = 1'b1;
                    endcase
                end

                4'h1: begin
                    rs1_used_o = 1'b1;
                    reg_write_o = 1'b1;
                    alu_src_imm_o = 1'b1;

                    case (op_d)
                        4'h0: begin
                            alu_op_o = ALU_ADD;
                            imm_o = sext16(imm16_d);
                        end
                        4'h1: begin
                            alu_op_o = ALU_AND;
                            imm_o = zext16(imm16_d);
                        end
                        4'h2: begin
                            alu_op_o = ALU_OR;
                            imm_o = zext16(imm16_d);
                        end
                        4'h3: begin
                            alu_op_o = ALU_XOR;
                            imm_o = zext16(imm16_d);
                        end
                        4'h4: begin
                            is_lui_o = 1'b1;
                            rs1_used_o = 1'b0;
                            imm_o = zext16(imm16_d);
                            if (rs1_d != 4'h0) begin
                                illegal_o = 1'b1;
                            end
                        end
                        4'h5: begin
                            alu_op_o = ALU_SLL;
                            imm_o = {27'h0, imm16_d[4:0]};
                            if (imm16_d[15:5] != 11'h000) begin
                                illegal_o = 1'b1;
                            end
                        end
                        4'h6: begin
                            alu_op_o = ALU_SRL;
                            imm_o = {27'h0, imm16_d[4:0]};
                            if (imm16_d[15:5] != 11'h000) begin
                                illegal_o = 1'b1;
                            end
                        end
                        4'h7: begin
                            alu_op_o = ALU_SRA;
                            imm_o = {27'h0, imm16_d[4:0]};
                            if (imm16_d[15:5] != 11'h000) begin
                                illegal_o = 1'b1;
                            end
                        end
                        default: illegal_o = 1'b1;
                    endcase
                end

                4'h2: begin
                    rs1_used_o = 1'b1;
                    reg_write_o = 1'b1;
                    mem_read_o = 1'b1;
                    alu_src_imm_o = 1'b1;
                    alu_op_o = ALU_ADD;
                    imm_o = sext16(imm16_d);

                    case (op_d)
                        4'h0: begin
                            mem_size_o = SIZE_BYTE;
                            load_sign_ext_o = 1'b1;
                        end
                        4'h1: begin
                            mem_size_o = SIZE_BYTE;
                            load_sign_ext_o = 1'b0;
                        end
                        4'h2: begin
                            mem_size_o = SIZE_HALF;
                            load_sign_ext_o = 1'b1;
                        end
                        4'h3: begin
                            mem_size_o = SIZE_HALF;
                            load_sign_ext_o = 1'b0;
                        end
                        4'h4: begin
                            mem_size_o = SIZE_WORD;
                            load_sign_ext_o = 1'b0;
                        end
                        default: illegal_o = 1'b1;
                    endcase
                end

                4'h3: begin
                    rs1_used_o = 1'b1;
                    rs2_used_o = 1'b1;
                    mem_write_o = 1'b1;
                    alu_src_imm_o = 1'b1;
                    alu_op_o = ALU_ADD;
                    imm_o = sext16(imm16_split_d);

                    case (op_d)
                        4'h0: mem_size_o = SIZE_BYTE;
                        4'h1: mem_size_o = SIZE_HALF;
                        4'h2: mem_size_o = SIZE_WORD;
                        default: illegal_o = 1'b1;
                    endcase
                end

                4'h4: begin
                    rs1_used_o = 1'b1;
                    rs2_used_o = 1'b1;
                    imm_o = sext16_shift2(imm16_split_d);

                    case (op_d)
                        4'h0: begin
                            branch_type_o = BR_UNCOND;
                            rs1_used_o = 1'b0;
                            rs2_used_o = 1'b0;
                            if ((rs1_d != 4'h0) || (rs2_d != 4'h0)) begin
                                illegal_o = 1'b1;
                            end else if (imm16_split_d == 16'h0000) begin
                                is_halt_o = 1'b1;
                            end
                        end
                        4'h1: branch_type_o = BR_EQ;
                        4'h2: branch_type_o = BR_NE;
                        4'h3: branch_type_o = BR_LT;
                        4'h4: branch_type_o = BR_LTU;
                        default: illegal_o = 1'b1;
                    endcase
                end

                4'h5: begin
                    reg_write_o = 1'b1;
                    case (op_d)
                        4'h0: begin
                            is_jal_o = 1'b1;
                            imm_o = sext20_shift2(off20_d);
                        end
                        4'h1: begin
                            is_jalr_o = 1'b1;
                            rs1_used_o = 1'b1;
                            imm_o = sext16(imm16_d);
                        end
                        4'h2: begin
                            is_lpc_o = 1'b1;
                            imm_o = sext20_shift2(off20_d);
                        end
                        default: illegal_o = 1'b1;
                    endcase
                end

                default: illegal_o = 1'b1;
            endcase
        end
    end
endmodule
