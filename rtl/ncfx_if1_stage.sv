//
// ncfx_if1_stage.sv
// NeoCoreFX - IF1 (PC select + fetch request)
//

module ncfx_if1_stage #(
    parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        stall_i,

    input  logic        redirect_valid_i,
    input  logic [31:0] redirect_pc_i,

    input  logic        pred_valid_i,
    input  logic        pred_taken_i,
    input  logic [31:0] pred_target_i,

    output logic        i_req_o,
    output logic [31:0] i_addr_o,

    output logic        if2_valid_o,
    output logic [31:0] if2_pc_o,
    output logic        if2_pred_taken_o,

    output logic [31:0] pc_o
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [31:0] pc_q;
    logic [31:0] fetch_pc;
    logic        pred_take;

    always_comb begin
        pred_take = pred_valid_i && pred_taken_i;
        fetch_pc = pc_q;

        if (redirect_valid_i) begin
            fetch_pc = redirect_pc_i;
        end else if (pred_take) begin
            fetch_pc = pred_target_i;
        end
    end

    assign i_req_o  = !rst && !stall_i;
    assign i_addr_o = fetch_pc;
    assign pc_o     = pc_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            pc_q             <= RESET_PC;
            if2_valid_o      <= 1'b0;
            if2_pc_o         <= RESET_PC;
            if2_pred_taken_o <= 1'b0;
        end else if (!stall_i) begin
            if2_valid_o      <= 1'b1;
            if2_pc_o         <= fetch_pc;
            if2_pred_taken_o <= pred_take && !redirect_valid_i;
            pc_q             <= fetch_pc + 32'd4;
        end
    end
endmodule
