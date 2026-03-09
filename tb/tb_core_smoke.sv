//
// tb_core_smoke.sv
// NeoCoreFX - Integrated core smoke testbench
//

`timescale 1ns/1ps

module tb_core_smoke;
  localparam int CLK_HALF_PERIOD_NS = 5;
  localparam int MAX_CYCLES = 500;

  // ==========================================================================
  // Testbench signals
  // ==========================================================================

  logic clk;
  logic rst_n;

  logic [7:0]  count;
  logic        halted;
  logic [31:0] current_pc;
  logic [31:0] cycle_count;
  logic [31:0] retire_count;
  logic [31:0] branch_redirect_count;
  logic [31:0] load_stall_count;
  logic [31:0] mem_stall_count;
  logic        wb_fault;

  int pass_count;
  int fail_count;

  // ==========================================================================
  // DUT
  // ==========================================================================

  neocorefx_top dut (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .en                     (1'b1),
    .count                  (count),
    .halted_o               (halted),
    .current_pc_o           (current_pc),
    .cycle_count_o          (cycle_count),
    .retire_count_o         (retire_count),
    .branch_redirect_count_o(branch_redirect_count),
    .load_stall_count_o     (load_stall_count),
    .mem_stall_count_o      (mem_stall_count),
    .wb_fault_o             (wb_fault)
  );

  // ==========================================================================
  // Clock generation
  // ==========================================================================

  always begin
    #(CLK_HALF_PERIOD_NS) clk = ~clk;
  end

  // ==========================================================================
  // Helpers
  // ==========================================================================

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

  task automatic write_byte(input logic [31:0] addr, input logic [7:0] data);
    logic [13:0] word_idx;
    begin
      word_idx = addr[15:2];
      case (addr[1:0])
        2'b00: dut.u_mem.mem[word_idx][31:24] = data;
        2'b01: dut.u_mem.mem[word_idx][23:16] = data;
        2'b10: dut.u_mem.mem[word_idx][15:8] = data;
        default: dut.u_mem.mem[word_idx][7:0] = data;
      endcase
    end
  endtask

  task automatic write_word(input logic [31:0] addr, input logic [31:0] data);
    begin
      write_byte(addr + 32'd0, data[31:24]);
      write_byte(addr + 32'd1, data[23:16]);
      write_byte(addr + 32'd2, data[15:8]);
      write_byte(addr + 32'd3, data[7:0]);
    end
  endtask

  task automatic clear_memory;
    int i;
    begin
      for (i = 0; i < 16384; i = i + 1) begin
        dut.u_mem.mem[i] = 32'h0000_0000;
      end
    end
  endtask

  // ==========================================================================
  // Test sequence
  // ==========================================================================

  initial begin
    int timeout;

    clk = 1'b0;
    rst_n = 1'b0;
    pass_count = 0;
    fail_count = 0;

    if ($test$plusargs("WAVES")) begin
      $dumpfile("tb_core_smoke.vcd");
      $dumpvars(0, tb_core_smoke);
    end

    repeat (4) @(posedge clk);

    clear_memory();

    // Program:
    //   ADDI 1, 0, 5
    //   ADDI 2, 1, 7
    //   ADD  3, 1, 2
    //   SUB  4, 3, 1
    //   B .
    write_word(32'h0000_0000, 32'h1010_0005);
    write_word(32'h0000_0004, 32'h1021_0007);
    write_word(32'h0000_0008, 32'h0131_2000);
    write_word(32'h0000_000C, 32'h0243_1000);
    write_word(32'h0000_0010, 32'h4000_0000);

    rst_n <= 1'b1;

    timeout = 0;
    while (!halted && (timeout < MAX_CYCLES)) begin
      @(posedge clk);
      timeout = timeout + 1;
    end

    check_true(halted, "Core halts on B . alias");
    check_true(!wb_fault, "No writeback fault during smoke program");

    check_eq32(dut.u_core.u_regfile.regs[1], 32'h0000_0005, "R1 after ADDI");
    check_eq32(dut.u_core.u_regfile.regs[2], 32'h0000_000C, "R2 with forwarded ADDI");
    check_eq32(dut.u_core.u_regfile.regs[3], 32'h0000_0011, "R3 chained ADD result");
    check_eq32(dut.u_core.u_regfile.regs[4], 32'h0000_000C, "R4 SUB result");
    check_eq32(mem_stall_count, 32'h0000_0000, "No memory-wait stall in ALU-only smoke");

    $display("========================================");
    $display("NeoCoreFX Smoke Results");
    $display("  cycles              : %0d", cycle_count);
    $display("  retired             : %0d", retire_count);
    $display("  redirects           : %0d", branch_redirect_count);
    $display("  load stalls         : %0d", load_stall_count);
    $display("  mem stalls          : %0d", mem_stall_count);
    $display("  final PC            : 0x%08h", current_pc);
    $display("  pass/fail           : %0d / %0d", pass_count, fail_count);
    $display("========================================");

    if (fail_count != 0) begin
      $fatal(1, "tb_core_smoke failed");
    end

    $finish;
  end
endmodule
