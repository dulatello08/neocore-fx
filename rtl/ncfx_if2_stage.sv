//
// ncfx_if2_stage.sv
// NeoCoreFX - IF2 (fetch response latch + static BTFNT prediction)
//

module ncfx_if2_stage
  import ncfx_core_pkg::*;
(
    input  logic        clk,
    input  logic        rst,
    input  logic        stall_i,
    input  logic        flush_i,

    input  logic        if1_valid_i,
    input  logic [31:0] if1_pc_i,
    input  logic        if1_pred_taken_i,

    input  logic        i_done_i,
    input  logic [31:0] i_rdata_i,
    input  logic        i_err_i,

    output logic        id_valid_o,
    output logic [31:0] id_pc_o,
    output logic [31:0] id_inst_o,
    output logic        id_pred_taken_o,
    output logic        id_fetch_fault_o,

    output logic        pred_valid_o,
    output logic        pred_taken_o,
    output logic [31:0] pred_target_o
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [3:0]  class_f;
    logic [3:0]  op_f;
    logic [15:0] off16_f;
    logic [19:0] off20_f;

    logic [31:0] branch_target_f;
    logic [31:0] jal_target_f;

    always_comb begin
        class_f = i_rdata_i[31:28];
        op_f = i_rdata_i[27:24];
        off16_f = {i_rdata_i[23:20], i_rdata_i[11:0]};
        off20_f = i_rdata_i[19:0];

        branch_target_f = if1_pc_i + ncfx_sext16_shift2(off16_f);
        jal_target_f = if1_pc_i + ncfx_sext20_shift2(off20_f);

        pred_valid_o = 1'b0;
        pred_taken_o = 1'b0;
        pred_target_o = 32'h0000_0000;

        if (if1_valid_i && i_done_i && !i_err_i) begin
            if (class_f == 4'h4) begin
                case (op_f)
                    4'h0: begin
                        pred_valid_o = 1'b1;
                        pred_taken_o = 1'b1;
                        pred_target_o = branch_target_f;
                    end
                    4'h1, 4'h2, 4'h3, 4'h4: begin
                        pred_valid_o = 1'b1;
                        pred_taken_o = off16_f[15];
                        pred_target_o = branch_target_f;
                    end
                    default: begin
                        pred_valid_o = 1'b0;
                        pred_taken_o = 1'b0;
                        pred_target_o = 32'h0000_0000;
                    end
                endcase
            end else if ((class_f == 4'h5) && (op_f == 4'h0)) begin
                pred_valid_o = 1'b1;
                pred_taken_o = 1'b1;
                pred_target_o = jal_target_f;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            id_valid_o       <= 1'b0;
            id_pc_o          <= 32'h0000_0000;
            id_inst_o        <= 32'h0000_0000;
            id_pred_taken_o  <= 1'b0;
            id_fetch_fault_o <= 1'b0;
        end else if (!stall_i) begin
            if (flush_i) begin
                id_valid_o       <= 1'b0;
                id_pc_o          <= 32'h0000_0000;
                id_inst_o        <= 32'h0000_0000;
                id_pred_taken_o  <= 1'b0;
                id_fetch_fault_o <= 1'b0;
            end else if (if1_valid_i && i_done_i) begin
                id_valid_o       <= 1'b1;
                id_pc_o          <= if1_pc_i;
                id_inst_o        <= i_rdata_i;
                id_pred_taken_o  <= if1_pred_taken_i;
                id_fetch_fault_o <= i_err_i;
            end else begin
                id_valid_o       <= 1'b0;
                id_pc_o          <= 32'h0000_0000;
                id_inst_o        <= 32'h0000_0000;
                id_pred_taken_o  <= 1'b0;
                id_fetch_fault_o <= 1'b0;
            end
        end
    end
endmodule
