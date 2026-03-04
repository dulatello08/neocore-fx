//
// id_stage.sv
// NeoCoreFX - ID (decode + hazard detect + ID/EX register + halt tagging)
//

module id_stage
  import core_pkg::*;
(
    // Clock/reset and pipeline control.
    input  logic        clk,
    input  logic        rst,
    input  logic        stall_i,
    input  logic        flush_i,
    input  logic        bubble_i,

    // IF2 pipeline inputs.
    input  logic        if2_valid_i,
    input  logic [31:0] if2_pc_i,
    input  logic [31:0] if2_inst_i,
    input  logic        if2_pred_taken_i,
    input  logic        if2_fetch_fault_i,

    // Register file interface.
    output logic [3:0]  rf_rs1_addr_o,
    output logic [3:0]  rf_rs2_addr_o,
    input  logic [31:0] rf_rs1_data_i,
    input  logic [31:0] rf_rs2_data_i,

    // Execute-stage hazard/forward context.
    input  logic        exe_valid_i,
    input  logic [3:0]  exe_rd_i,
    input  logic        exe_reg_write_i,
    input  logic        exe_mem_read_i,

    // Memory-stage hazard/forward context.
    input  logic        mem_valid_i,
    input  logic [3:0]  mem_rd_i,
    input  logic        mem_reg_write_i,

    // Writeback-stage hazard/forward context.
    input  logic        wb_valid_i,
    input  logic [3:0]  wb_rd_i,
    input  logic        wb_reg_write_i,

    // Stall request for load-use hazard.
    output logic        load_use_stall_o,

    // ID -> EXE pipeline outputs.
    output logic        idex_valid_o,
    output logic [31:0] idex_pc_o,
    output logic [3:0]  idex_rd_o,
    output logic [3:0]  idex_rs1_addr_o,
    output logic [3:0]  idex_rs2_addr_o,
    output logic [31:0] idex_rs1_data_o,
    output logic [31:0] idex_rs2_data_o,
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
    // Halt metadata for `B .` alias.
    output logic        idex_is_halt_o,
    output logic        idex_pred_taken_o,
    output logic        idex_fetch_fault_o,
    output logic [1:0]  idex_fwd_rs1_sel_o,
    output logic [1:0]  idex_fwd_rs2_sel_o,
    output logic        idex_illegal_o
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [3:0]  class_d;
    logic [3:0]  op_d;
    logic [3:0]  rd_d;
    logic [3:0]  rs1_d;
    logic [3:0]  rs2_d;
    logic [11:0] ext12_d;
    logic [15:0] imm16_d;
    logic [15:0] imm16_split_d;
    logic [19:0] off20_d;

    logic rs1_used_d;
    logic rs2_used_d;

    logic [31:0]      imm_d;
    alu_op_t     alu_op_d;
    branch_t     branch_type_d;
    fwd_sel_t    fwd_rs1_sel_d;
    fwd_sel_t    fwd_rs2_sel_d;
    mem_size_t   mem_size_d;

    logic alu_src_imm_d;
    logic mem_read_d;
    logic mem_write_d;
    logic load_sign_ext_d;
    logic reg_write_d;
    logic is_jal_d;
    logic is_jalr_d;
    logic is_lui_d;
    logic is_lpc_d;
    logic is_halt_d;
    logic illegal_d;

    logic rs1_hazard_d;
    logic rs2_hazard_d;

    always_comb begin
        class_d = if2_inst_i[31:28];
        op_d = if2_inst_i[27:24];
        rd_d = if2_inst_i[23:20];
        rs1_d = if2_inst_i[19:16];
        rs2_d = if2_inst_i[15:12];
        ext12_d = if2_inst_i[11:0];
        imm16_d = if2_inst_i[15:0];
        imm16_split_d = {if2_inst_i[23:20], if2_inst_i[11:0]};
        off20_d = if2_inst_i[19:0];

        rf_rs1_addr_o = rs1_d;
        rf_rs2_addr_o = rs2_d;

        rs1_used_d = 1'b0;
        rs2_used_d = 1'b0;
        imm_d = 32'h0000_0000;
        alu_op_d = ALU_ADD;
        branch_type_d = BR_NONE;
        alu_src_imm_d = 1'b0;
        mem_read_d = 1'b0;
        mem_write_d = 1'b0;
        mem_size_d = SIZE_WORD;
        load_sign_ext_d = 1'b0;
        reg_write_d = 1'b0;
        is_jal_d = 1'b0;
        is_jalr_d = 1'b0;
        is_lui_d = 1'b0;
        is_lpc_d = 1'b0;
        is_halt_d = 1'b0;
        illegal_d = 1'b0;

        if (if2_inst_i != 32'h0000_0000) begin
            case (class_d)
                4'h0: begin
                    rs1_used_d = 1'b1;
                    rs2_used_d = 1'b1;
                    reg_write_d = 1'b1;

                    if (ext12_d != 12'h000) begin
                        illegal_d = 1'b1;
                    end

                    case (op_d)
                        4'h1: alu_op_d = ALU_ADD;
                        4'h2: alu_op_d = ALU_SUB;
                        4'h3: alu_op_d = ALU_AND;
                        4'h4: alu_op_d = ALU_OR;
                        4'h5: alu_op_d = ALU_XOR;
                        4'h6: alu_op_d = ALU_SLT;
                        4'h7: alu_op_d = ALU_SLTU;
                        4'h8: alu_op_d = ALU_SLL;
                        4'h9: alu_op_d = ALU_SRL;
                        4'hA: alu_op_d = ALU_SRA;
                        4'hB: alu_op_d = ALU_MUL;
                        4'hC: alu_op_d = ALU_MULH;
                        4'hD: alu_op_d = ALU_MULHU;
                        4'hE: alu_op_d = ALU_MULHSU;
                        default: illegal_d = 1'b1;
                    endcase
                end

                4'h1: begin
                    rs1_used_d = 1'b1;
                    reg_write_d = 1'b1;
                    alu_src_imm_d = 1'b1;

                    case (op_d)
                        4'h0: begin
                            alu_op_d = ALU_ADD;
                            imm_d = sext16(imm16_d);
                        end
                        4'h1: begin
                            alu_op_d = ALU_AND;
                            imm_d = zext16(imm16_d);
                        end
                        4'h2: begin
                            alu_op_d = ALU_OR;
                            imm_d = zext16(imm16_d);
                        end
                        4'h3: begin
                            alu_op_d = ALU_XOR;
                            imm_d = zext16(imm16_d);
                        end
                        4'h4: begin
                            is_lui_d = 1'b1;
                            rs1_used_d = 1'b0;
                            imm_d = zext16(imm16_d);
                            if (rs1_d != 4'h0) begin
                                illegal_d = 1'b1;
                            end
                        end
                        4'h5: begin
                            alu_op_d = ALU_SLL;
                            imm_d = {27'h0, imm16_d[4:0]};
                            if (imm16_d[15:5] != 11'h000) begin
                                illegal_d = 1'b1;
                            end
                        end
                        4'h6: begin
                            alu_op_d = ALU_SRL;
                            imm_d = {27'h0, imm16_d[4:0]};
                            if (imm16_d[15:5] != 11'h000) begin
                                illegal_d = 1'b1;
                            end
                        end
                        4'h7: begin
                            alu_op_d = ALU_SRA;
                            imm_d = {27'h0, imm16_d[4:0]};
                            if (imm16_d[15:5] != 11'h000) begin
                                illegal_d = 1'b1;
                            end
                        end
                        default: illegal_d = 1'b1;
                    endcase
                end

                4'h2: begin
                    rs1_used_d = 1'b1;
                    reg_write_d = 1'b1;
                    mem_read_d = 1'b1;
                    alu_src_imm_d = 1'b1;
                    alu_op_d = ALU_ADD;
                    imm_d = sext16(imm16_d);

                    case (op_d)
                        4'h0: begin
                            mem_size_d = SIZE_BYTE;
                            load_sign_ext_d = 1'b1;
                        end
                        4'h1: begin
                            mem_size_d = SIZE_BYTE;
                            load_sign_ext_d = 1'b0;
                        end
                        4'h2: begin
                            mem_size_d = SIZE_HALF;
                            load_sign_ext_d = 1'b1;
                        end
                        4'h3: begin
                            mem_size_d = SIZE_HALF;
                            load_sign_ext_d = 1'b0;
                        end
                        4'h4: begin
                            mem_size_d = SIZE_WORD;
                            load_sign_ext_d = 1'b0;
                        end
                        default: illegal_d = 1'b1;
                    endcase
                end

                4'h3: begin
                    rs1_used_d = 1'b1;
                    rs2_used_d = 1'b1;
                    mem_write_d = 1'b1;
                    alu_src_imm_d = 1'b1;
                    alu_op_d = ALU_ADD;
                    imm_d = sext16(imm16_split_d);

                    case (op_d)
                        4'h0: mem_size_d = SIZE_BYTE;
                        4'h1: mem_size_d = SIZE_HALF;
                        4'h2: mem_size_d = SIZE_WORD;
                        default: illegal_d = 1'b1;
                    endcase
                end

                4'h4: begin
                    rs1_used_d = 1'b1;
                    rs2_used_d = 1'b1;
                    imm_d = sext16_shift2(imm16_split_d);

                    case (op_d)
                        4'h0: begin
                            branch_type_d = BR_UNCOND;
                            rs1_used_d = 1'b0;
                            rs2_used_d = 1'b0;
                            if ((rs1_d != 4'h0) || (rs2_d != 4'h0)) begin
                                illegal_d = 1'b1;
                            end else if (imm16_split_d == 16'h0000) begin
                                // HALT alias: B . (branch to current PC).
                                is_halt_d = 1'b1;
                            end
                        end
                        4'h1: branch_type_d = BR_EQ;
                        4'h2: branch_type_d = BR_NE;
                        4'h3: branch_type_d = BR_LT;
                        4'h4: branch_type_d = BR_LTU;
                        default: illegal_d = 1'b1;
                    endcase
                end

                4'h5: begin
                    reg_write_d = 1'b1;

                    case (op_d)
                        4'h0: begin
                            is_jal_d = 1'b1;
                            imm_d = sext20_shift2(off20_d);
                        end
                        4'h1: begin
                            is_jalr_d = 1'b1;
                            rs1_used_d = 1'b1;
                            imm_d = sext16(imm16_d);
                        end
                        4'h2: begin
                            is_lpc_d = 1'b1;
                            imm_d = sext20_shift2(off20_d);
                        end
                        default: illegal_d = 1'b1;
                    endcase
                end

                default: illegal_d = 1'b1;
            endcase
        end

        if (illegal_d) begin
            reg_write_d = 1'b0;
            mem_read_d = 1'b0;
            mem_write_d = 1'b0;
            branch_type_d = BR_NONE;
            is_jal_d = 1'b0;
            is_jalr_d = 1'b0;
            is_lui_d = 1'b0;
            is_lpc_d = 1'b0;
            is_halt_d = 1'b0;
        end

        rs1_hazard_d = rs1_used_d && (exe_rd_i == rs1_d);
        rs2_hazard_d = rs2_used_d && (exe_rd_i == rs2_d);

        load_use_stall_o = if2_valid_i
                        && exe_valid_i
                        && exe_mem_read_i
                        && (exe_rd_i != 4'h0)
                        && (rs1_hazard_d || rs2_hazard_d);

        fwd_rs1_sel_d = FWD_NONE;
        if (rs1_used_d && (rs1_d != 4'h0)) begin
            if (exe_valid_i && exe_reg_write_i && !exe_mem_read_i
             && (exe_rd_i == rs1_d) && (exe_rd_i != 4'h0)) begin
                fwd_rs1_sel_d = FWD_MEM;
            end else if (mem_valid_i && mem_reg_write_i
                      && (mem_rd_i == rs1_d) && (mem_rd_i != 4'h0)) begin
                fwd_rs1_sel_d = FWD_WB;
            end else if (wb_valid_i && wb_reg_write_i
                      && (wb_rd_i == rs1_d) && (wb_rd_i != 4'h0)) begin
                fwd_rs1_sel_d = FWD_WB;
            end
        end

        fwd_rs2_sel_d = FWD_NONE;
        if (rs2_used_d && (rs2_d != 4'h0)) begin
            if (exe_valid_i && exe_reg_write_i && !exe_mem_read_i
             && (exe_rd_i == rs2_d) && (exe_rd_i != 4'h0)) begin
                fwd_rs2_sel_d = FWD_MEM;
            end else if (mem_valid_i && mem_reg_write_i
                      && (mem_rd_i == rs2_d) && (mem_rd_i != 4'h0)) begin
                fwd_rs2_sel_d = FWD_WB;
            end else if (wb_valid_i && wb_reg_write_i
                      && (wb_rd_i == rs2_d) && (wb_rd_i != 4'h0)) begin
                fwd_rs2_sel_d = FWD_WB;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            idex_valid_o         <= 1'b0;
            idex_pc_o            <= 32'h0000_0000;
            idex_rd_o            <= 4'h0;
            idex_rs1_addr_o      <= 4'h0;
            idex_rs2_addr_o      <= 4'h0;
            idex_rs1_data_o      <= 32'h0000_0000;
            idex_rs2_data_o      <= 32'h0000_0000;
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
            idex_fetch_fault_o   <= 1'b0;
            idex_fwd_rs1_sel_o   <= FWD_NONE;
            idex_fwd_rs2_sel_o   <= FWD_NONE;
            idex_illegal_o       <= 1'b0;
        end else if (!stall_i) begin
            if (flush_i || bubble_i) begin
                idex_valid_o         <= 1'b0;
                idex_pc_o            <= 32'h0000_0000;
                idex_rd_o            <= 4'h0;
                idex_rs1_addr_o      <= 4'h0;
                idex_rs2_addr_o      <= 4'h0;
                idex_rs1_data_o      <= 32'h0000_0000;
                idex_rs2_data_o      <= 32'h0000_0000;
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
                idex_fetch_fault_o   <= 1'b0;
                idex_fwd_rs1_sel_o   <= FWD_NONE;
                idex_fwd_rs2_sel_o   <= FWD_NONE;
                idex_illegal_o       <= 1'b0;
            end else begin
                idex_valid_o         <= if2_valid_i;
                idex_pc_o            <= if2_pc_i;
                idex_rd_o            <= rd_d;
                idex_rs1_addr_o      <= rs1_d;
                idex_rs2_addr_o      <= rs2_d;
                idex_rs1_data_o      <= rf_rs1_data_i;
                idex_rs2_data_o      <= rf_rs2_data_i;
                idex_imm_o           <= imm_d;
                idex_alu_op_o        <= alu_op_d;
                idex_alu_src_imm_o   <= alu_src_imm_d;
                idex_mem_read_o      <= mem_read_d;
                idex_mem_write_o     <= mem_write_d;
                idex_mem_size_o      <= mem_size_d;
                idex_load_sign_ext_o <= load_sign_ext_d;
                idex_reg_write_o     <= reg_write_d;
                idex_branch_type_o   <= branch_type_d;
                idex_is_jal_o        <= is_jal_d;
                idex_is_jalr_o       <= is_jalr_d;
                idex_is_lui_o        <= is_lui_d;
                idex_is_lpc_o        <= is_lpc_d;
                idex_is_halt_o       <= is_halt_d;
                idex_pred_taken_o    <= if2_pred_taken_i;
                idex_fetch_fault_o   <= if2_fetch_fault_i;
                idex_fwd_rs1_sel_o   <= fwd_rs1_sel_d;
                idex_fwd_rs2_sel_o   <= fwd_rs2_sel_d;
                idex_illegal_o       <= illegal_d;
            end
        end
    end
endmodule
