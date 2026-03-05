//
// tb_core_any.sv
// NeoCoreFX - Generic integrated-core testbench
//
// Loads a byte-per-line hex program into BRAM with +PROGRAM=<path>.
//

`timescale 1ns/1ps

module tb_core_any;
  localparam int CLK_HALF_PERIOD_NS = 5;
  localparam int MAX_CYCLES_DEFAULT = 300000;

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

  logic debug_enabled;
  logic profile_enabled;

  int max_cycles;

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
  // Memory access helpers
  // ==========================================================================

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

  function automatic logic [7:0] read_byte(input logic [31:0] addr);
    logic [13:0] word_idx;
    begin
      word_idx = addr[15:2];
      case (addr[1:0])
        2'b00: read_byte = dut.u_mem.mem[word_idx][31:24];
        2'b01: read_byte = dut.u_mem.mem[word_idx][23:16];
        2'b10: read_byte = dut.u_mem.mem[word_idx][15:8];
        default: read_byte = dut.u_mem.mem[word_idx][7:0];
      endcase
    end
  endfunction

  task automatic clear_memory;
    int i;
    begin
      for (i = 0; i < 16384; i = i + 1) begin
        dut.u_mem.mem[i] = 32'h0000_0000;
      end
    end
  endtask

  task automatic load_program_file(input string program_file, output int bytes_loaded);
    int fd;
    int byte_val;
    int addr;
    begin
      fd = $fopen(program_file, "r");
      if (fd == 0) begin
        $display("ERROR: Could not open program file: %s", program_file);
        $finish;
      end

      addr = 0;
      bytes_loaded = 0;
      while (!$feof(fd)) begin
        if ($fscanf(fd, "%h", byte_val) == 1) begin
          write_byte(addr, byte_val[7:0]);
          if (debug_enabled && (addr < 32)) begin
            $display("DEBUG: load addr=0x%04h data=0x%02h", addr[15:0], byte_val[7:0]);
          end
          addr = addr + 1;
          bytes_loaded = bytes_loaded + 1;
        end
      end

      $fclose(fd);
    end
  endtask

  task automatic dump_registers;
    int i;
    begin
      $display("Register Dump (hex):");
      $display("========================================");
      for (i = 0; i < 16; i = i + 1) begin
        $display("R%2d = 0x%08h", i, dut.u_core.u_regfile.regs[i]);
      end
      $display("========================================");
    end
  endtask

  task automatic dump_memory_window(input logic [31:0] base_addr, input int lines);
    int line;
    int b;
    logic [31:0] addr;
    begin
      for (line = 0; line < lines; line = line + 1) begin
        addr = base_addr + line * 16;
        $write("%04h:", addr[15:0]);
        for (b = 0; b < 16; b = b + 1) begin
          $write(" %02h", read_byte(addr + b));
        end
        $write("\n");
      end
    end
  endtask

  // ==========================================================================
  // Optional debug stream
  // ==========================================================================

  always @(posedge clk) begin
    if (debug_enabled && rst_n) begin
      $display("Cycle %0d: PC=0x%08h Halt=%b Count=0x%02h WB_Fault=%b", 
               cycle_count, current_pc, halted, count, wb_fault);
      $display("         Stall(load/mem)=%0d/%0d Redirects=%0d Retired=%0d",
               load_stall_count, mem_stall_count,
               branch_redirect_count, retire_count);
    end
  end

  // ==========================================================================
  // Test sequence
  // ==========================================================================

  initial begin
    string program_file;
    int bytes_loaded;
    int timeout;

    clk = 1'b0;
    rst_n = 1'b0;
    debug_enabled = 1'b0;
    profile_enabled = 1'b0;
    max_cycles = MAX_CYCLES_DEFAULT;

    if ($test$plusargs("DEBUG")) begin
      debug_enabled = 1'b1;
    end
    if ($test$plusargs("PROFILE")) begin
      profile_enabled = 1'b1;
    end
    if ($value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
      // Override accepted.
    end

    if ($test$plusargs("WAVES")) begin
      $dumpfile("tb_core_any.vcd");
      $dumpvars(0, tb_core_any);
    end

    if (!$value$plusargs("PROGRAM=%s", program_file)) begin
      program_file = "mem/test_smoke.hex";
    end

    $display("========================================");
    $display("NeoCoreFX Generic Program Test");
    $display("  PROGRAM     : %s", program_file);
    $display("  MAX_CYCLES  : %0d", max_cycles);
    if (debug_enabled) $display("  DEBUG       : enabled");
    if (profile_enabled) $display("  PROFILE     : enabled");
    $display("========================================\n");

    repeat (4) @(posedge clk);

    clear_memory();
    load_program_file(program_file, bytes_loaded);

    $display("Loaded %0d bytes from %s", bytes_loaded, program_file);

    if (profile_enabled) begin
      $display("Program hexdump [0x0000..0x003F]:");
      dump_memory_window(32'h0000_0000, 4);
    end

    rst_n <= 1'b1;

    timeout = 0;
    while (!halted && (timeout < max_cycles)) begin
      @(posedge clk);
      timeout = timeout + 1;
    end

    if (!halted) begin
      $display("\n========================================");
      $display("ERROR: timeout after %0d cycles", timeout);
      $display("PC = 0x%08h Halted = %b", current_pc, halted);
      $display("========================================");
      dump_registers();
      $fatal(1, "tb_core_any timeout");
    end

    repeat (3) @(posedge clk);

    $display("\n========================================");
    $display("Program halted at PC = 0x%08h", current_pc);
    $display("Total cycles: %0d", cycle_count);
    $display("Retired instructions: %0d", retire_count);
    if (cycle_count != 0) begin
      $display("IPC (retired): %.3f", 1.0 * retire_count / cycle_count);
    end
    $display("Redirect count: %0d", branch_redirect_count);
    $display("Load-use stall cycles: %0d", load_stall_count);
    $display("Memory wait stall cycles: %0d", mem_stall_count);
    $display("WB fault seen: %0d", wb_fault);
    $display("========================================");

    if (profile_enabled) begin
      $display("\nMemory hexdump [0x0000..0x00FF]:");
      dump_memory_window(32'h0000_0000, 16);
    end

    $display("");
    dump_registers();

    $finish;
  end
endmodule
