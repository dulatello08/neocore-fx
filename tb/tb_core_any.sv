//
// tb_core_any.sv
// NeoCoreFX - Generic integrated-core testbench
//
// Loads a byte-per-line hex program into BRAM with +PROGRAM=<path>.
//

`timescale 1ns/1ps

module tb_core_any;
  localparam int CLK_HALF_PERIOD_NS = 5;
  localparam int MAX_CYCLES_DEFAULT = 1000000;

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

  logic debug_enabled;
  logic profile_enabled;
  logic trace_pc_window_enabled;

  logic [31:0] trace_pc_lo;
  logic [31:0] trace_pc_hi;
  logic        trace_pc_in_window;

  int max_cycles;
  int trace_pc_limit;
  int trace_pc_count;

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

  assign trace_pc_in_window = (current_pc >= trace_pc_lo) && (current_pc <= trace_pc_hi);

  // ==========================================================================
  // Memory access helpers
  // ==========================================================================

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

  function automatic logic [7:0] read_byte(input logic [31:0] addr);
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
        2'b00: read_byte = dut.u_mem.u_bram.bank_gen[0].mem[row_addr][8*(3-byte_sel) +: 8];
        2'b01: read_byte = dut.u_mem.u_bram.bank_gen[1].mem[row_addr][8*(3-byte_sel) +: 8];
        2'b10: read_byte = dut.u_mem.u_bram.bank_gen[2].mem[row_addr][8*(3-byte_sel) +: 8];
        default: read_byte = dut.u_mem.u_bram.bank_gen[3].mem[row_addr][8*(3-byte_sel) +: 8];
      endcase
    end
  endfunction

  function automatic logic [31:0] read_word(input logic [31:0] addr);
    begin
      read_word = {read_byte(addr + 0),
                   read_byte(addr + 1),
                   read_byte(addr + 2),
                   read_byte(addr + 3)};
    end
  endfunction

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
    if (debug_enabled && top_rst_btn_n) begin
      $display("Cycle %0d: PC=0x%08h Halt=%b Count=0x%02h WB_Fault=%b",
               cycle_count, current_pc, halted, count, wb_fault);
      $display("         Stall(load/mem)=%0d/%0d Redirects=%0d Retired=%0d",
               load_stall_count, mem_stall_count,
               branch_redirect_count, retire_count);
    end

    if (trace_pc_window_enabled
     && top_rst_btn_n
     && trace_pc_in_window
     && ((trace_pc_limit == 0) || (trace_pc_count < trace_pc_limit))) begin
      trace_pc_count = trace_pc_count + 1;
      $display("TRACE[%0d] cyc=%0d pc=0x%08h insn=0x%08h halt=%b wb_fault=%b count=0x%02h",
               trace_pc_count, cycle_count, current_pc, read_word(current_pc),
               halted, wb_fault, count);
      $display("       regs r2=0x%08h r3=0x%08h r4=0x%08h r15=0x%08h",
               dut.u_core.u_regfile.regs[2], dut.u_core.u_regfile.regs[3],
               dut.u_core.u_regfile.regs[4], dut.u_core.u_regfile.regs[15]);
      $display("       idex valid=%b pc=0x%08h imm=0x%08h br_t=0x%0h pred=%b jal=%b jalr=%b rs1=0x%08h rs2=0x%08h",
               dut.u_core.idex_valid, dut.u_core.idex_pc, dut.u_core.idex_imm,
               dut.u_core.idex_branch_type, dut.u_core.idex_pred_taken,
               dut.u_core.idex_is_jal, dut.u_core.idex_is_jalr,
               dut.u_core.u_stages.idex_rs1_data, dut.u_core.u_stages.idex_rs2_data);
      $display("       exe rs1_f=0x%08h rs2_f=0x%08h br_taken=%b act_taken=%b act_tgt=0x%08h redir_v=%b redir_pc=0x%08h mispred=%b",
               dut.u_core.u_stages.u_exe.rs1_final, dut.u_core.u_stages.u_exe.rs2_final,
               dut.u_core.u_stages.u_exe.branch_taken, dut.u_core.u_stages.u_exe.actual_taken,
               dut.u_core.u_stages.u_exe.actual_target, dut.u_core.redirect_valid,
               dut.u_core.redirect_pc, dut.u_core.mispredict);
      $display("       stalls load=%0d mem=%0d redirects=%0d retired=%0d mem_wait=%b load_use=%b",
               load_stall_count, mem_stall_count,
               branch_redirect_count, retire_count,
               dut.u_core.mem_wait_stall, dut.u_core.load_use_stall);
      $display("       dbus cyc=%b stb=%b we=%b ack=%b err=%b sel=0x%1h addr=0x%08h wdata=0x%08h rdata=0x%08h",
               dut.u_mem.dbus_cyc, dut.u_mem.dbus_stb, dut.u_mem.dbus_we,
               dut.u_mem.dbus_ack, dut.u_mem.dbus_err, dut.u_mem.dbus_sel,
               dut.u_mem.dbus_addr, dut.u_mem.dbus_wdata, dut.u_mem.dbus_rdata);
      $display("       uart req=%b req_valid=%b wait_rel=%b wait_cyc=%b ack=%b err=%b tx_count=%0d tx_active=%b tx_bit=%0d baud=%0d ctrl=0x%08h",
               dut.u_mem.m_sel_uart, dut.u_mem.u_uart_console.req_valid_q,
               dut.u_mem.u_uart_console.req_wait_release_q, dut.u_mem.u_uart_console.req_wait_cycle_q,
               dut.u_mem.u_uart_console.ack_o, dut.u_mem.u_uart_console.err_o,
               dut.u_mem.u_uart_console.tx_count_q, dut.u_mem.u_uart_console.tx_active_q,
               dut.u_mem.u_uart_console.tx_bit_idx_q, dut.u_mem.u_uart_console.bauddiv_q,
               dut.u_mem.u_uart_console.ctrl_q);
    end
  end

  // ==========================================================================
  // Test sequence
  // ==========================================================================

  initial begin
    string program_file;
    int bytes_loaded;
    int timeout;
    int uart_drain_cycles;

    clk = 1'b0;
    top_rst_btn_n = 1'b0;
    debug_enabled = 1'b0;
    profile_enabled = 1'b0;
    trace_pc_window_enabled = 1'b0;

    trace_pc_lo = 32'h0000_0d80;
    trace_pc_hi = 32'h0000_0dac;
    trace_pc_limit = 256;
    trace_pc_count = 0;

    max_cycles = MAX_CYCLES_DEFAULT;

    if ($test$plusargs("DEBUG")) begin
      debug_enabled = 1'b1;
    end
    if ($test$plusargs("PROFILE")) begin
      profile_enabled = 1'b1;
    end
    if ($test$plusargs("TRACE_PC_WINDOW")) begin
      trace_pc_window_enabled = 1'b1;
    end
    if ($value$plusargs("TRACE_PC_LO=%h", trace_pc_lo)) begin
      // Override accepted.
    end
    if ($value$plusargs("TRACE_PC_HI=%h", trace_pc_hi)) begin
      // Override accepted.
    end
    if ($value$plusargs("TRACE_PC_LIMIT=%d", trace_pc_limit)) begin
      // Override accepted.
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
    if (trace_pc_window_enabled) begin
      $display("  TRACE_PC    : enabled [0x%08h..0x%08h], limit=%0d",
               trace_pc_lo, trace_pc_hi, trace_pc_limit);
    end
    $display("========================================\n");

    repeat (4) @(posedge clk);

    clear_memory();
    load_program_file(program_file, bytes_loaded);

    $display("Loaded %0d bytes from %s", bytes_loaded, program_file);

    if (profile_enabled) begin
      $display("Program hexdump [0x0000..0x003F]:");
      dump_memory_window(32'h0000_0000, 4);
    end

    top_rst_btn_n <= 1'b1;

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

    uart_drain_cycles = 0;
    while ((dut.u_mem.u_uart_console.tx_active_q || (dut.u_mem.u_uart_console.tx_count_q != 0))
        && (uart_drain_cycles < max_cycles)) begin
      @(posedge clk);
      uart_drain_cycles = uart_drain_cycles + 1;
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
    $display("UART drain cycles after halt: %0d", uart_drain_cycles);
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
