//
// if2_stage.sv
// NeoCoreFX - IF2 (fetch response latch + static BTFNT prediction)
//

module if2_stage
  import core_pkg::*;
(
    // Clock/reset and pipeline control.
    input  logic        clk,
    input  logic        rst,
    input  logic        stall_i,
    input  logic        flush_i,

    // IF1 pipeline inputs.
    input  logic        if1_valid_i,
    input  logic [31:0] if1_pc_i,
    input  logic        if1_pred_taken_i,

    // BIU instruction response.
    input  logic        i_done_i,
    input  logic [31:0] i_rdata_i,
    input  logic        i_err_i,

    // IF2 -> ID pipeline outputs.
    output logic        id_valid_o,
    output logic [31:0] id_pc_o,
    output logic [31:0] id_inst_o,
    output logic        id_pred_taken_o,
    output logic        id_fetch_fault_o,

    // Predictor feedback toward IF1.
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

    logic        resp_valid_live;
    logic [31:0] resp_pc_live;
    logic [31:0] resp_inst_live;
    logic        resp_err_live;

    logic        resp_pending_q;
    logic [31:0] resp_pending_pc_q;
    logic [31:0] resp_pending_inst_q;
    logic        resp_pending_err_q;

    logic        resp_valid_d;
    logic [31:0] resp_pc_d;
    logic [31:0] resp_inst_d;
    logic        resp_err_d;

    logic        pred_for_inst_valid_d;
    logic        pred_for_inst_taken_d;
    logic [31:0] branch_target_f;
    logic [31:0] jal_target_f;

    assign resp_valid_live = if1_valid_i && i_done_i;
    assign resp_pc_live = if1_pc_i;
    assign resp_inst_live = i_rdata_i;
    assign resp_err_live = i_err_i;

    assign resp_valid_d = resp_pending_q ? 1'b1 : resp_valid_live;
    assign resp_pc_d = resp_pending_q ? resp_pending_pc_q : resp_pc_live;
    assign resp_inst_d = resp_pending_q ? resp_pending_inst_q : resp_inst_live;
    assign resp_err_d = resp_pending_q ? resp_pending_err_q : resp_err_live;

    assign class_f = resp_inst_d[31:28];
    assign op_f = resp_inst_d[27:24];
    assign off16_f = {resp_inst_d[23:20], resp_inst_d[11:0]};
    assign off20_f = resp_inst_d[19:0];

    assign branch_target_f = resp_pc_d + sext16_shift2(off16_f);
    assign jal_target_f = resp_pc_d + sext20_shift2(off20_f);

    always_comb begin
        pred_for_inst_valid_d = 1'b0;
        pred_for_inst_taken_d = 1'b0;

        pred_valid_o = 1'b0;
        pred_taken_o = 1'b0;
        pred_target_o = 32'h0000_0000;

        if (resp_valid_d && !resp_err_d) begin
            if (class_f == 4'h4) begin
                case (op_f)
                    4'h0: begin
                        pred_for_inst_valid_d = 1'b1;
                        pred_for_inst_taken_d = 1'b1;
                        pred_target_o = branch_target_f;
                    end
                    4'h1, 4'h2, 4'h3, 4'h4: begin
                        pred_for_inst_valid_d = 1'b1;
                        pred_for_inst_taken_d = off16_f[15];
                        pred_target_o = branch_target_f;
                    end
                    default: begin end
                endcase
            end else if ((class_f == 4'h5) && (op_f == 4'h0)) begin
                pred_for_inst_valid_d = 1'b1;
                pred_for_inst_taken_d = 1'b1;
                pred_target_o = jal_target_f;
            end
        end

        pred_valid_o = !stall_i && !flush_i && pred_for_inst_valid_d;
        pred_taken_o = pred_valid_o && pred_for_inst_taken_d;
        if (!pred_valid_o) begin
            pred_target_o = 32'h0000_0000;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            id_valid_o       <= 1'b0;
            id_pc_o          <= 32'h0000_0000;
            id_inst_o        <= 32'h0000_0000;
            id_pred_taken_o  <= 1'b0;
            id_fetch_fault_o <= 1'b0;
            resp_pending_q   <= 1'b0;
            resp_pending_pc_q <= 32'h0000_0000;
            resp_pending_inst_q <= 32'h0000_0000;
            resp_pending_err_q <= 1'b0;
        end else if (flush_i) begin
            id_valid_o       <= 1'b0;
            id_pc_o          <= 32'h0000_0000;
            id_inst_o        <= 32'h0000_0000;
            id_pred_taken_o  <= 1'b0;
            id_fetch_fault_o <= 1'b0;
            resp_pending_q   <= 1'b0;
            resp_pending_pc_q <= 32'h0000_0000;
            resp_pending_inst_q <= 32'h0000_0000;
            resp_pending_err_q <= 1'b0;
        end else if (stall_i) begin
            if (!resp_pending_q && resp_valid_live) begin
                resp_pending_q <= 1'b1;
                resp_pending_pc_q <= resp_pc_live;
                resp_pending_inst_q <= resp_inst_live;
                resp_pending_err_q <= resp_err_live;
            end
        end else if (!stall_i) begin
            if (resp_valid_d) begin
                id_valid_o       <= 1'b1;
                id_pc_o          <= resp_pc_d;
                id_inst_o        <= resp_inst_d;
                id_pred_taken_o  <= pred_for_inst_valid_d && pred_for_inst_taken_d;
                id_fetch_fault_o <= resp_err_d;
            end else begin
                id_valid_o       <= 1'b0;
                id_pc_o          <= 32'h0000_0000;
                id_inst_o        <= 32'h0000_0000;
                id_pred_taken_o  <= 1'b0;
                id_fetch_fault_o <= 1'b0;
            end

            if (resp_pending_q) begin
                resp_pending_q <= 1'b0;
            end
        end
    end

    logic unused_if1_pred_taken;
    assign unused_if1_pred_taken = if1_pred_taken_i;
endmodule
