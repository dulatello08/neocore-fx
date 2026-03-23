//
// tb_mem.sv
// Unit testbench for memory model
//

`timescale 1ns/1ps

module tb_mem;
    import mem_pkg::*;

    localparam int CLK_HALF_PERIOD_NS = 5;

    // Clock/reset.
    logic        clk;
    logic        rst;

    // I-Bus interface.
    logic        ibus_cyc;
    logic        ibus_stb;
    logic [31:0] ibus_addr;
    logic        ibus_ack;
    logic [31:0] ibus_rdata;
    logic        ibus_err;

    // D-Bus interface.
    logic        dbus_cyc;
    logic        dbus_stb;
    logic        dbus_we;
    logic [31:0] dbus_addr;
    logic [31:0] dbus_wdata;
    logic [3:0]  dbus_sel;
    logic        dbus_ack;
    logic [31:0] dbus_rdata;
    logic        dbus_err;
    logic        uart_rx;
    logic        uart_tx;

    // Scoreboard counters.
    int pass_count;
    int fail_count;

    mem dut (
        .clk        (clk),
        .rst        (rst),
        .ibus_cyc   (ibus_cyc),
        .ibus_stb   (ibus_stb),
        .ibus_addr  (ibus_addr),
        .ibus_ack   (ibus_ack),
        .ibus_rdata (ibus_rdata),
        .ibus_err   (ibus_err),
        .dbus_cyc   (dbus_cyc),
        .dbus_stb   (dbus_stb),
        .dbus_we    (dbus_we),
        .dbus_addr  (dbus_addr),
        .dbus_wdata (dbus_wdata),
        .dbus_sel   (dbus_sel),
        .dbus_ack   (dbus_ack),
        .dbus_rdata (dbus_rdata),
        .dbus_err   (dbus_err),
        .uart_rx_i  (uart_rx),
        .uart_tx_o  (uart_tx)
    );

    always begin
        #(CLK_HALF_PERIOD_NS) clk = ~clk;
    end

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

    task automatic ibus_read(
        input  logic [31:0] addr,
        output logic [31:0] rdata,
        output bit          ack_seen,
        output bit          err_seen
    );
        begin
            ibus_cyc  <= 1'b1;
            ibus_stb  <= 1'b1;
            ibus_addr <= addr;

            @(posedge clk);
            // 1-cycle latency: ack + rdata are registered on this edge
            ibus_cyc  <= 1'b0;
            ibus_stb  <= 1'b0;
            ibus_addr <= 32'h0000_0000;

            #1;
            rdata    = ibus_rdata;
            ack_seen = ibus_ack;
            err_seen = ibus_err;
        end
    endtask

    task automatic dbus_xact(
        input  logic        we,
        input  logic [31:0] addr,
        input  logic [31:0] wdata,
        input  logic [3:0]  sel,
        output logic [31:0] rdata,
        output bit          ack_seen,
        output bit          err_seen
    );
        begin
            dbus_cyc   <= 1'b1;
            dbus_stb   <= 1'b1;
            dbus_we    <= we;
            dbus_addr  <= addr;
            dbus_wdata <= wdata;
            dbus_sel   <= sel;

            @(posedge clk);
            // 1-cycle latency: ack + rdata are registered on this edge
            dbus_cyc   <= 1'b0;
            dbus_stb   <= 1'b0;
            dbus_we    <= 1'b0;
            dbus_addr  <= 32'h0000_0000;
            dbus_wdata <= 32'h0000_0000;
            dbus_sel   <= 4'b0000;

            #1;
            rdata    = dbus_rdata;
            ack_seen = dbus_ack;
            err_seen = dbus_err;
        end
    endtask

    initial begin
        logic [31:0] rd;
        bit          ack_seen;
        bit          err_seen;

        clk = 1'b0;
        rst = 1'b1;
        ibus_cyc = 1'b0;
        ibus_stb = 1'b0;
        ibus_addr = 32'h0000_0000;
        dbus_cyc = 1'b0;
        dbus_stb = 1'b0;
        dbus_we = 1'b0;
        dbus_addr = 32'h0000_0000;
        dbus_wdata = 32'h0000_0000;
        dbus_sel = 4'b0000;
        uart_rx = 1'b1;
        pass_count = 0;
        fail_count = 0;

        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_mem.vcd");
            $dumpvars(0, tb_mem);
        end

        repeat (4) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
        #1;

        check_true(!ibus_ack && !ibus_err, "I-Bus outputs idle after reset");
        check_true(!dbus_ack && !dbus_err, "D-Bus outputs idle after reset");

        ibus_read(32'h0000_0000, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "I-Bus read at 0x0 returns ack");
        check_eq32(rd, 32'h0000_0000, "I-Bus default read data is zero");

        dbus_xact(1'b1, 32'h0000_0020, 32'h1122_3344, 4'b1111, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "D-Bus full-word write acks");

        dbus_xact(1'b0, 32'h0000_0020, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "D-Bus read acks after full-word write");
        check_eq32(rd, 32'h1122_3344, "D-Bus readback matches full-word write");

        ibus_read(32'h0000_0020, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "I-Bus read acks on written location");
        check_eq32(rd, 32'h1122_3344, "I-Bus readback sees D-Bus write");

        dbus_xact(1'b1, 32'h0000_0020, 32'hAA00_0000, 4'b1000, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "D-Bus byte-lane write (sel[3]) acks");
        dbus_xact(1'b0, 32'h0000_0020, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_eq32(rd, 32'hAA22_3344, "Byte lane 3 write updates MSB byte only");

        dbus_xact(1'b1, 32'h0000_0020, 32'h0000_BEEF, 4'b0011, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "D-Bus lower-half write acks");
        dbus_xact(1'b0, 32'h0000_0020, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_eq32(rd, 32'hAA22_BEEF, "Lower-half lane write updates bytes [15:0]");

        dbus_xact(1'b1, 32'h0000_0020, 32'hFFFF_FFFF, 4'b0000, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "D-Bus write with sel=0 still acks");
        dbus_xact(1'b0, 32'h0000_0020, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_eq32(rd, 32'hAA22_BEEF, "Write with sel=0 does not alter memory");

        dbus_xact(1'b1, UART_BASE_ADDR + UART_TXDATA_OFFSET, 32'h0000_0041, 4'b1111, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "UART TX write acks");

        dbus_xact(1'b0, UART_BASE_ADDR + UART_STATUS_OFFSET, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "UART STATUS read acks");
        check_true(rd[0], "UART status reports TX ready");
        check_true(!rd[1], "UART status reports RX empty by default");

        dbus_xact(1'b1, UART_BASE_ADDR + UART_CTRL_OFFSET, 32'h0000_0001, 4'b1111, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "UART CTRL write acks");
        dbus_xact(1'b0, UART_BASE_ADDR + UART_CTRL_OFFSET, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_eq32(rd, 32'h0000_0001, "UART CTRL write/readback matches");
        dbus_xact(1'b1, UART_BASE_ADDR + UART_CTRL_OFFSET, 32'h0000_0003, 4'b1111, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "UART CTRL re-enable write acks");

        dbus_xact(1'b1, UART_BASE_ADDR + UART_RXDATA_OFFSET, 32'h0000_005A, 4'b1111, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "UART RX inject write acks");
        dbus_xact(1'b0, UART_BASE_ADDR + UART_STATUS_OFFSET, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_true(rd[1], "UART status reports RX valid after inject");
        dbus_xact(1'b0, UART_BASE_ADDR + UART_RXDATA_OFFSET, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_eq32(rd, 32'h5A5A_5A5A, "UART RX read returns injected byte");
        dbus_xact(1'b0, UART_BASE_ADDR + UART_STATUS_OFFSET, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_true(!rd[1], "UART status clears RX valid after RX read");

        // Force TX FIFO full and confirm TXDATA write is backpressured.
        dut.u_uart.tx_count_q = 5'd16;
        dut.u_uart.tx_active_q = 1'b1;
        dut.u_uart.tx_bit_idx_q = 4'd0;
        dut.u_uart.tx_baud_cnt_q = 32'd0;
        dut.u_uart.bauddiv_q = 32'd1000;
        dbus_xact(1'b1, UART_BASE_ADDR + UART_TXDATA_OFFSET, 32'h0000_0042, 4'b1111, rd, ack_seen, err_seen);
        check_true(!ack_seen && !err_seen, "UART TX write stalls when FIFO is full");
        dut.u_uart.tx_count_q = 5'd15;
        dut.u_uart.tx_active_q = 1'b0;
        dbus_xact(1'b1, UART_BASE_ADDR + UART_TXDATA_OFFSET, 32'h0000_0042, 4'b1111, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "UART TX write resumes once FIFO has space");

        // Hold request high one extra cycle after ack; UART must not replay write.
        dut.u_uart.ctrl_q = 32'h0000_0003;
        dut.u_uart.tx_wr_ptr_q = 4'd0;
        dut.u_uart.tx_rd_ptr_q = 4'd0;
        dut.u_uart.tx_count_q = 5'd0;
        dut.u_uart.tx_active_q = 1'b1;
        dut.u_uart.tx_bit_idx_q = 4'd0;
        dut.u_uart.tx_baud_cnt_q = 32'd0;
        dut.u_uart.bauddiv_q = 32'd1000;

        dbus_cyc   <= 1'b1;
        dbus_stb   <= 1'b1;
        dbus_we    <= 1'b1;
        dbus_addr  <= UART_BASE_ADDR + UART_TXDATA_OFFSET;
        dbus_wdata <= 32'h0000_0051;
        dbus_sel   <= 4'b1111;
        @(posedge clk);
        #1;
        check_true(dbus_ack && !dbus_err, "UART TX write acks on first cycle");
        check_true(dut.u_uart.tx_count_q == 5'd1, "UART TX FIFO increments exactly once");

        @(posedge clk);
        #1;
        check_true(!dbus_ack && !dbus_err, "UART does not replay ack while request level remains high");
        check_true(dut.u_uart.tx_count_q == 5'd1, "UART TX FIFO count unchanged during held request");

        // Repeating the same request for another cycle must progress (no
        // deadlock on identical back-to-back writes).
        @(posedge clk);
        #1;
        check_true(dbus_ack && !dbus_err, "UART accepts identical write after one-cycle holdoff");
        check_true(dut.u_uart.tx_count_q == 5'd2, "UART TX FIFO increments on identical back-to-back write");

        dbus_cyc   <= 1'b0;
        dbus_stb   <= 1'b0;
        dbus_we    <= 1'b0;
        dbus_addr  <= 32'h0000_0000;
        dbus_wdata <= 32'h0000_0000;
        dbus_sel   <= 4'b0000;
        @(posedge clk);
        #1;

        dbus_xact(1'b0, 32'h0001_0000, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_true(!ack_seen && err_seen, "D-Bus read outside mapped memory returns err");

        dbus_xact(1'b1, 32'h0001_0000, 32'hDEAD_BEEF, 4'b1111, rd, ack_seen, err_seen);
        check_true(!ack_seen && err_seen, "D-Bus write outside mapped memory returns err");

        ibus_read(32'h0001_0000, rd, ack_seen, err_seen);
        check_true(!ack_seen && err_seen, "I-Bus read outside mapped memory returns err");

        dbus_xact(1'b0, MMIO_BASE_ADDR + 32'h200, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_true(!ack_seen && err_seen, "D-Bus read to unmapped MMIO slot returns err");

        ibus_read(32'h0000_0002, rd, ack_seen, err_seen);
        check_true(!ack_seen && err_seen, "I-Bus misaligned fetch returns err");

        dbus_xact(1'b1, 32'h0000_0030, 32'hDEAD_BEEF, 4'b1111, rd, ack_seen, err_seen);
        check_true(ack_seen && !err_seen, "Seed write for concurrent read test");

        // Fire both I-Bus and D-Bus reads in the same cycle.
        // Both are 1-cycle latency — acks should arrive together.
        ibus_cyc   <= 1'b1;
        ibus_stb   <= 1'b1;
        ibus_addr  <= 32'h0000_0030;
        dbus_cyc   <= 1'b1;
        dbus_stb   <= 1'b1;
        dbus_we    <= 1'b0;
        dbus_addr  <= 32'h0000_0030;
        dbus_wdata <= 32'h0000_0000;
        dbus_sel   <= 4'b1111;

        @(posedge clk);
        // Both acks arrive on this edge (1-cycle)
        ibus_cyc   <= 1'b0;
        ibus_stb   <= 1'b0;
        ibus_addr  <= 32'h0000_0000;
        dbus_cyc   <= 1'b0;
        dbus_stb   <= 1'b0;
        dbus_we    <= 1'b0;
        dbus_addr  <= 32'h0000_0000;
        dbus_wdata <= 32'h0000_0000;
        dbus_sel   <= 4'b0000;

        #1;
        check_true(ibus_ack && !ibus_err, "Concurrent I-Bus read acks");
        check_true(dbus_ack && !dbus_err, "Concurrent D-Bus read acks");
        check_eq32(ibus_rdata, 32'hDEAD_BEEF, "Concurrent I-Bus read data matches");
        check_eq32(dbus_rdata, 32'hDEAD_BEEF, "Concurrent D-Bus read data matches");

        @(posedge clk);
        #1;
        check_true(!ibus_ack && !dbus_ack, "Both ack pulses cleared");

        $display("PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count != 0) begin
            $fatal(1, "tb_mem failed");
        end
        $finish;
    end
endmodule
