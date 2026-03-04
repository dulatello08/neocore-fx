//
// tb_mem.sv
// Unit testbench for memory model
//

`timescale 1ns/1ps

module tb_mem;
    localparam int CLK_HALF_PERIOD_NS = 5;

    // Clock/reset.
    logic        clk;
    logic        rst_n;

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

    // Scoreboard counters.
    int pass_count;
    int fail_count;

    mem dut (
        .clk        (clk),
        .rst_n      (rst_n),
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
        .dbus_err   (dbus_err)
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
        rst_n = 1'b0;
        ibus_cyc = 1'b0;
        ibus_stb = 1'b0;
        ibus_addr = 32'h0000_0000;
        dbus_cyc = 1'b0;
        dbus_stb = 1'b0;
        dbus_we = 1'b0;
        dbus_addr = 32'h0000_0000;
        dbus_wdata = 32'h0000_0000;
        dbus_sel = 4'b0000;
        pass_count = 0;
        fail_count = 0;

        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_mem.vcd");
            $dumpvars(0, tb_mem);
        end

        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
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

        dbus_xact(1'b0, 32'h0001_0000, 32'h0000_0000, 4'b1111, rd, ack_seen, err_seen);
        check_true(!ack_seen && err_seen, "D-Bus read outside mapped memory returns err");

        dbus_xact(1'b1, 32'h0001_0000, 32'hDEAD_BEEF, 4'b1111, rd, ack_seen, err_seen);
        check_true(!ack_seen && err_seen, "D-Bus write outside mapped memory returns err");

        ibus_read(32'h0001_0000, rd, ack_seen, err_seen);
        check_true(!ack_seen && err_seen, "I-Bus read outside mapped memory returns err");

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
