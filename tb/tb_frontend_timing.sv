//
// tb_frontend_timing.sv
// NeoCoreFX - Frontend stall/redirect timing regression bench
//

`timescale 1ns/1ps

module tb_frontend_timing;
  localparam int CLK_HALF_PERIOD_NS = 5;

  logic clk;
  logic rst;

  logic        if1_stall;
  logic        if2_stall;
  logic        if2_flush;
  logic        redirect_valid;
  logic [31:0] redirect_pc;

  logic        i_done;
  logic [31:0] i_rdata;
  logic        i_err;

  logic        i_req;
  logic [31:0] i_addr;

  logic        if1_if2_valid;
  logic [31:0] if1_if2_pc;
  logic        if1_if2_pred_taken;
  logic [31:0] if1_pc;

  logic        if2_if1_valid;
  logic [31:0] if2_if1_pc;
  logic        if2_if1_pred_taken;

  logic        id_valid;
  logic [31:0] id_pc;
  logic [31:0] id_inst;
  logic        id_pred_taken;
  logic [31:0] id_pred_target;
  logic        id_fetch_fault;

  logic        pred_valid;
  logic        pred_taken;
  logic [31:0] pred_target;

  int pass_count;
  int fail_count;

  always begin
    #(CLK_HALF_PERIOD_NS) clk = ~clk;
  end

  if1_stage u_if1 (
    .clk              (clk),
    .rst              (rst),
    .stall_i          (if1_stall),
    .redirect_valid_i (redirect_valid),
    .redirect_pc_i    (redirect_pc),
    .pred_valid_i     (1'b0),
    .pred_taken_i     (1'b0),
    .pred_target_i    (32'h0000_0000),
    .i_req_o          (i_req),
    .i_addr_o         (i_addr),
    .if2_valid_o      (if1_if2_valid),
    .if2_pc_o         (if1_if2_pc),
    .if2_pred_taken_o (if1_if2_pred_taken),
    .pc_o             (if1_pc)
  );

  if2_stage u_if2 (
    .clk              (clk),
    .rst              (rst),
    .stall_i          (if2_stall),
    .flush_i          (if2_flush),
    .if1_valid_i      (if2_if1_valid),
    .if1_pc_i         (if2_if1_pc),
    .if1_pred_taken_i (if2_if1_pred_taken),
    .bp_update_valid_i(1'b0),
    .bp_update_pc_i   (32'h0000_0000),
    .bp_update_taken_i(1'b0),
    .ras_push_valid_i (1'b0),
    .ras_push_addr_i  (32'h0000_0000),
    .ras_pop_valid_i  (1'b0),
    .i_done_i         (i_done),
    .i_rdata_i        (i_rdata),
    .i_err_i          (i_err),
    .id_valid_o       (id_valid),
    .id_pc_o          (id_pc),
    .id_inst_o        (id_inst),
    .id_pred_taken_o  (id_pred_taken),
    .id_pred_target_o (id_pred_target),
    .id_fetch_fault_o (id_fetch_fault),
    .pred_valid_o     (pred_valid),
    .pred_taken_o     (pred_taken),
    .pred_target_o    (pred_target)
  );

  task automatic check_true(input bit cond, input string msg);
    if (!cond) begin
      fail_count = fail_count + 1;
      $error("FAIL: %s", msg);
    end else begin
      pass_count = pass_count + 1;
    end
  endtask

  task automatic check_eq32(
    input logic [31:0] got,
    input logic [31:0] exp,
    input string       msg
  );
    if (got !== exp) begin
      fail_count = fail_count + 1;
      $error("FAIL: %s expected=0x%08x got=0x%08x", msg, exp, got);
    end else begin
      pass_count = pass_count + 1;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    if1_stall = 1'b0;
    if2_stall = 1'b0;
    if2_flush = 1'b0;
    redirect_valid = 1'b0;
    redirect_pc = 32'h0000_0000;
    i_done = 1'b0;
    i_rdata = 32'h0000_0000;
    i_err = 1'b0;
    if2_if1_valid = 1'b0;
    if2_if1_pc = 32'h0000_0000;
    if2_if1_pred_taken = 1'b0;
    pass_count = 0;
    fail_count = 0;

    if ($test$plusargs("WAVES")) begin
      $dumpfile("tb_frontend_timing.vcd");
      $dumpvars(0, tb_frontend_timing);
    end

    repeat (3) @(posedge clk);
    rst <= 1'b0;
    @(posedge clk);

    // -----------------------------------------------------------------------
    // Case 1: Redirect asserted while stalled must be replayed on release.
    // -----------------------------------------------------------------------
    if1_stall <= 1'b1;
    if2_stall <= 1'b1;
    redirect_pc <= 32'h0000_0080;
    redirect_valid <= 1'b1;
    @(posedge clk);
    redirect_valid <= 1'b0;
    check_true(!i_req, "No fetch request while IF1 is stalled");

    if1_stall <= 1'b0;
    if2_stall <= 1'b0;
    #1;
    check_true(i_req, "Fetch request resumes after stall release");
    check_eq32(i_addr, 32'h0000_0080, "Redirect target is issued after stall");
    @(posedge clk);
    #1;
    check_eq32(if1_pc, 32'h0000_0084, "IF1 architectural PC advances from redirect target");

    // -----------------------------------------------------------------------
    // Case 2: IF2 flush must clear ID packet even when IF2 is stalled.
    // -----------------------------------------------------------------------
    if2_if1_valid <= 1'b1;
    if2_if1_pc <= 32'h0000_0040;
    if2_if1_pred_taken <= 1'b0;
    i_done <= 1'b1;
    i_rdata <= 32'h0000_0000;
    @(posedge clk);
    #1;
    check_true(id_valid, "IF2 captures a packet before flush-stall test");

    if2_flush <= 1'b1;
    if2_stall <= 1'b1;
    i_done <= 1'b0;
    @(posedge clk);
    #1;
    check_true(!id_valid, "IF2 flush clears ID packet while stalled");

    if2_flush <= 1'b0;
    if2_stall <= 1'b0;
    @(posedge clk);

    // -----------------------------------------------------------------------
    // Case 3: Predictor feedback must be muted during stall/flush windows.
    // -----------------------------------------------------------------------
    if2_if1_valid <= 1'b1;
    if2_if1_pc <= 32'h0000_0100;
    if2_if1_pred_taken <= 1'b0;
    i_rdata <= 32'h4000_0000; // B . (always-taken branch class/op)
    i_done <= 1'b1;
    i_err <= 1'b0;

    if2_stall <= 1'b1;
    if2_flush <= 1'b0;
    #1;
    check_true(!pred_valid, "Predictor feedback is muted while IF2 is stalled");

    if2_stall <= 1'b0;
    if2_flush <= 1'b1;
    #1;
    check_true(!pred_valid, "Predictor feedback is muted while IF2 is flushed");

    if2_flush <= 1'b0;
    #1;
    check_true(pred_valid && pred_taken, "Predictor feedback resumes in normal flow");
    check_eq32(pred_target, if2_if1_pc, "B . predicts to current IF1 PC");

    $display("========================================");
    $display("NeoCoreFX Frontend Timing Regression");
    $display("  pass/fail           : %0d / %0d", pass_count, fail_count);
    $display("========================================");

    if (fail_count != 0) begin
      $fatal(1, "tb_frontend_timing failed");
    end

    $finish;
  end
endmodule
