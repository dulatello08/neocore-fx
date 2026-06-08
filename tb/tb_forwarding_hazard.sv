//
// tb_forwarding_hazard.sv
// NeoCoreFX - Regression for stale WB-forward select hazard.
//

`timescale 1ns/1ps

module tb_forwarding_hazard;
  localparam int CLK_HALF_PERIOD_NS = 5;
  localparam int MAX_CYCLES = 500;

  // ==========================================================================
  // Testbench signals
  // ==========================================================================

  logic clk;
  logic top_rst_btn_n;

  logic [7:0]  count;
  logic        uart_tx;
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
    .rst_btn_n              (top_rst_btn_n),
    .uart_rx_i              (1'b1),
    .uart_tx_o              (uart_tx),
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
    logic [1:0] bank_sel;
    logic [11:0] row_addr;
    logic [1:0] byte_sel;
    begin
      word_idx = addr[15:2];
      bank_sel = word_idx[1:0];
      row_addr = word_idx[13:2];
      byte_sel = addr[1:0];
      case (bank_sel)
        2'b00: dut.u_mem.u_bram.bank_gen[0].mem[row_addr][8*(3-byte_sel) +: 8] = data;
        2'b01: dut.u_mem.u_bram.bank_gen[1].mem[row_addr][8*(3-byte_sel) +: 8] = data;
        2'b10: dut.u_mem.u_bram.bank_gen[2].mem[row_addr][8*(3-byte_sel) +: 8] = data;
        default: dut.u_mem.u_bram.bank_gen[3].mem[row_addr][8*(3-byte_sel) +: 8] = data;
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
      for (i = 0; i < 4096; i = i + 1) begin
        dut.u_mem.u_bram.bank_gen[0].mem[i] = 32'h0000_0000;
        dut.u_mem.u_bram.bank_gen[1].mem[i] = 32'h0000_0000;
        dut.u_mem.u_bram.bank_gen[2].mem[i] = 32'h0000_0000;
        dut.u_mem.u_bram.bank_gen[3].mem[i] = 32'h0000_0000;
      end
    end
  endtask

  // ==========================================================================
  // Test sequence
  // ==========================================================================

  initial begin
    int timeout;

    clk = 1'b0;
    top_rst_btn_n = 1'b0;
    pass_count = 0;
    fail_count = 0;

    if ($test$plusargs("WAVES")) begin
      $dumpfile("tb_forwarding_hazard.vcd");
      $dumpvars(0, tb_forwarding_hazard);
    end

    repeat (4) @(posedge clk);

    clear_memory();

    // Target sequence:
    //   ADDI 1, 0, 5
    //   ADDI 2, 1, 7
    //   ADD  3, 1, 2
    //   ADDI 5, 0, 1
    //   SUB  4, 2, 1   <-- old bug could pick stale WB data here
    //   B .
    write_word(32'h0000_0000, 32'h1010_0005);
    write_word(32'h0000_0004, 32'h1021_0007);
    write_word(32'h0000_0008, 32'h0131_2000);
    write_word(32'h0000_000C, 32'h1050_0001);
    write_word(32'h0000_0010, 32'h0242_1000);
    write_word(32'h0000_0014, 32'h4000_0000);

    top_rst_btn_n <= 1'b1;

    timeout = 0;
    while (!halted && (timeout < MAX_CYCLES)) begin
      @(posedge clk);
      timeout = timeout + 1;
    end

    check_true(halted, "Core halts on B . alias");
    check_true(!wb_fault, "No writeback fault during forwarding hazard regression");

    check_eq32(dut.u_core.u_regfile.regs[1], 32'h0000_0005, "R1 after ADDI");
    check_eq32(dut.u_core.u_regfile.regs[2], 32'h0000_000C, "R2 after ADDI dependency");
    check_eq32(dut.u_core.u_regfile.regs[3], 32'h0000_0011, "R3 after chained ADD");
    check_eq32(dut.u_core.u_regfile.regs[4], 32'h0000_0007, "R4 uses architectural R2 value");
    check_eq32(dut.u_core.u_regfile.regs[5], 32'h0000_0001, "R5 filler op result");

    check_eq32(retire_count, 32'h0000_0006, "All six instructions retire");
    check_eq32(load_stall_count, 32'h0000_0000, "No load-use stalls in ALU-only sequence");
    check_eq32(mem_stall_count, 32'h0000_0000, "No memory-wait stalls in ALU-only sequence");

    $display("========================================");
    $display("NeoCoreFX Forwarding Hazard Regression");
    $display("  cycles              : %0d", cycle_count);
    $display("  retired             : %0d", retire_count);
    $display("  redirects           : %0d", branch_redirect_count);
    $display("  load stalls         : %0d", load_stall_count);
    $display("  mem stalls          : %0d", mem_stall_count);
    $display("  final PC            : 0x%08h", current_pc);
    $display("  pass/fail           : %0d / %0d", pass_count, fail_count);
    $display("========================================");

    if (fail_count != 0) begin
      $fatal(1, "tb_forwarding_hazard failed");
    end

    $finish;
  end
endmodule
