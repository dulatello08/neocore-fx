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

    // Branch predictor training feedback from resolved EXE branches.
    input  logic        bp_update_valid_i,
    input  logic [31:0] bp_update_pc_i,
    input  logic        bp_update_taken_i,
    input  logic        ras_push_valid_i,
    input  logic [31:0] ras_push_addr_i,
    input  logic        ras_pop_valid_i,

    // BIU instruction response.
    input  logic        i_done_i,
    input  logic [31:0] i_rdata_i,
    input  logic        i_err_i,

    // IF2 -> ID pipeline outputs.
    output logic        id_valid_o,
    output logic [31:0] id_pc_o,
    output logic [31:0] id_inst_o,
    output logic        id_pred_taken_o,
    output logic [31:0] id_pred_target_o,
    output logic        id_fetch_fault_o,

    // Predictor feedback toward IF1.
    output logic        pred_valid_o,
    output logic        pred_taken_o,
    output logic [31:0] pred_target_o
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam int unsigned BHT_ENTRIES = 64;
    localparam int unsigned BHT_IDX_W = $clog2(BHT_ENTRIES);
    localparam int unsigned RAS_DEPTH = 4;
    localparam int unsigned RAS_SP_W = $clog2(RAS_DEPTH + 1);
    localparam logic [3:0] ABI_LR_REG = 4'hB;

    logic [3:0]  class_f;
    logic [3:0]  op_f;
    logic [3:0]  rd_f;
    logic [3:0]  rs1_f;
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
    logic [31:0] pred_for_inst_target_d;
    logic [31:0] branch_target_f;
    logic [31:0] jal_target_f;

    logic [BHT_IDX_W-1:0] bht_rd_idx_d;
    logic [BHT_IDX_W-1:0] bht_wr_idx_d;
    logic [1:0] bht_ctr_q [0:BHT_ENTRIES-1];
    logic       bht_valid_q [0:BHT_ENTRIES-1];
    logic [1:0] bht_ctr_rd_d;
    logic       bht_valid_rd_d;
    logic [31:0] ras_stack_q [0:RAS_DEPTH-1];
    logic [RAS_SP_W-1:0] ras_sp_q;
    logic [31:0] ras_top_d;
    logic        ras_has_entry_d;
    logic        is_ret_d;

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
    assign rd_f = resp_inst_d[23:20];
    assign rs1_f = resp_inst_d[19:16];
    assign off16_f = {resp_inst_d[23:20], resp_inst_d[11:0]};
    assign off20_f = resp_inst_d[19:0];

    assign branch_target_f = resp_pc_d + sext16_shift2(off16_f);
    assign jal_target_f = resp_pc_d + sext20_shift2(off20_f);
    assign bht_rd_idx_d = resp_pc_d[BHT_IDX_W+1:2];
    assign bht_wr_idx_d = bp_update_pc_i[BHT_IDX_W+1:2];
    assign bht_ctr_rd_d = bht_ctr_q[bht_rd_idx_d];
    assign bht_valid_rd_d = bht_valid_q[bht_rd_idx_d];
    assign ras_has_entry_d = (ras_sp_q != 0);
    assign ras_top_d = ras_has_entry_d ? ras_stack_q[ras_sp_q - 1'b1] : 32'h0000_0000;
    assign is_ret_d = (class_f == 4'h5) && (op_f == 4'h1)
                   && (rd_f == 4'h0) && (rs1_f == ABI_LR_REG) && (off16_f == 16'h0000);

    always_comb begin
        pred_for_inst_valid_d = 1'b0;
        pred_for_inst_taken_d = 1'b0;
        pred_for_inst_target_d = 32'h0000_0000;

        pred_valid_o = 1'b0;
        pred_taken_o = 1'b0;
        pred_target_o = 32'h0000_0000;

        if (resp_valid_d && !resp_err_d) begin
            if (class_f == 4'h4) begin
                case (op_f)
                    4'h0: begin
                        pred_for_inst_valid_d = 1'b1;
                        pred_for_inst_taken_d = 1'b1;
                        pred_for_inst_target_d = branch_target_f;
                    end
                    4'h1, 4'h2, 4'h3, 4'h4: begin
                        pred_for_inst_valid_d = 1'b1;
                        pred_for_inst_taken_d = bht_valid_rd_d ? bht_ctr_rd_d[1] : off16_f[15];
                        pred_for_inst_target_d = branch_target_f;
                    end
                    default: begin end
                endcase
            end else if ((class_f == 4'h5) && (op_f == 4'h0)) begin
                pred_for_inst_valid_d = 1'b1;
                pred_for_inst_taken_d = 1'b1;
                pred_for_inst_target_d = jal_target_f;
            end else if (is_ret_d && ras_has_entry_d) begin
                pred_for_inst_valid_d = 1'b1;
                pred_for_inst_taken_d = 1'b1;
                pred_for_inst_target_d = ras_top_d;
            end
        end

        pred_valid_o = !stall_i && !flush_i && pred_for_inst_valid_d;
        pred_taken_o = pred_valid_o && pred_for_inst_taken_d;
        pred_target_o = pred_taken_o ? pred_for_inst_target_d : 32'h0000_0000;
    end

    always_ff @(posedge clk) begin
        int i;
        if (rst) begin
            for (i = 0; i < BHT_ENTRIES; i++) begin
                bht_ctr_q[i] <= 2'b01;
                bht_valid_q[i] <= 1'b0;
            end
            ras_sp_q <= '0;
        end else if (bp_update_valid_i) begin
            bht_valid_q[bht_wr_idx_d] <= 1'b1;
            if (bp_update_taken_i) begin
                if (bht_ctr_q[bht_wr_idx_d] != 2'b11) begin
                    bht_ctr_q[bht_wr_idx_d] <= bht_ctr_q[bht_wr_idx_d] + 2'b01;
                end
            end else begin
                if (bht_ctr_q[bht_wr_idx_d] != 2'b00) begin
                    bht_ctr_q[bht_wr_idx_d] <= bht_ctr_q[bht_wr_idx_d] - 2'b01;
                end
            end
        end

        if (!rst) begin
            if (ras_pop_valid_i && (ras_sp_q != 0)) begin
                ras_sp_q <= ras_sp_q - 1'b1;
            end

            if (ras_push_valid_i) begin
                if (ras_pop_valid_i && (ras_sp_q != 0)) begin
                    ras_stack_q[ras_sp_q - 1'b1] <= ras_push_addr_i;
                end else if (ras_sp_q < RAS_DEPTH) begin
                    ras_stack_q[ras_sp_q] <= ras_push_addr_i;
                    ras_sp_q <= ras_sp_q + 1'b1;
                end else begin
                    ras_stack_q[RAS_DEPTH-1] <= ras_push_addr_i;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            id_valid_o       <= 1'b0;
            id_pc_o          <= 32'h0000_0000;
            id_inst_o        <= 32'h0000_0000;
            id_pred_taken_o  <= 1'b0;
            id_pred_target_o <= 32'h0000_0000;
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
            id_pred_target_o <= 32'h0000_0000;
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
                id_pred_target_o <= (pred_for_inst_valid_d && pred_for_inst_taken_d)
                                    ? pred_for_inst_target_d
                                    : 32'h0000_0000;
                id_fetch_fault_o <= resp_err_d;
            end else begin
                id_valid_o       <= 1'b0;
                id_pc_o          <= 32'h0000_0000;
                id_inst_o        <= 32'h0000_0000;
                id_pred_taken_o  <= 1'b0;
                id_pred_target_o <= 32'h0000_0000;
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
