//
// tb_biu.sv
// Integration testbench for BIU + memory model
//

`timescale 1ns/1ps

module tb_biu;
    localparam int CLK_HALF_PERIOD_NS = 5;

    // BIU data-size encodings.
    localparam logic [1:0] SIZE_BYTE = 2'b00;
    localparam logic [1:0] SIZE_HALF = 2'b01;
    localparam logic [1:0] SIZE_WORD = 2'b10;

    // Clock/reset.
    logic clk;
    logic rst;

    // CPU-side instruction port.
    logic        i_req;
    logic [31:0] i_addr;
    logic        i_busy;
    logic        i_done;
    logic [31:0] i_rdata;
    logic        i_err;

    // CPU-side data port.
    logic        d_req;
    logic        d_we;
    logic [1:0]  d_size;
    logic [31:0] d_addr;
    logic [31:0] d_wdata;
    logic        d_busy;
    logic        d_done;
    logic [31:0] d_rdata;
    logic        d_err;

    // Fabric-side instruction bus.
    logic        ibus_cyc;
    logic        ibus_stb;
    logic [31:0] ibus_addr;
    logic        ibus_ack;
    logic [31:0] ibus_rdata;
    logic        ibus_err;

    // Fabric-side data bus.
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

    biu u_biu (
        .clk        (clk),
        .rst        (rst),
        .i_req      (i_req),
        .i_addr     (i_addr),
        .i_busy     (i_busy),
        .i_done     (i_done),
        .i_rdata    (i_rdata),
        .i_err      (i_err),
        .d_req      (d_req),
        .d_we       (d_we),
        .d_size     (d_size),
        .d_addr     (d_addr),
        .d_wdata    (d_wdata),
        .d_busy     (d_busy),
        .d_done     (d_done),
        .d_rdata    (d_rdata),
        .d_err      (d_err),
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

    mem u_mem (
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
        .debug_enable_i(1'b0),
        .core_halted_i(1'b0),
        .core_current_pc_i(32'h0000_0000),
        .core_halt_reason_i(3'b000),
        .core_last_fault_i(1'b0),
        .core_last_fault_pc_i(32'h0000_0000),
        .core_last_fault_addr_i(32'h0000_0000),
        .core_last_illegal_inst_i(32'h0000_0000),
        .core_cycle_count_i(32'h0000_0000),
        .core_retire_count_i(32'h0000_0000),
        .core_redirect_count_i(32'h0000_0000),
        .core_load_stall_count_i(32'h0000_0000),
        .core_mem_stall_count_i(32'h0000_0000),
        .dbg_halt_req_o(),
        .dbg_resume_req_o(),
        .dbg_step_req_o(),
        .dbg_gpr_addr_o(),
        .dbg_gpr_rdata_i(32'h0000_0000),
        .dbg_gpr_we_o(),
        .dbg_gpr_wdata_o(),
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

    task automatic check_eq32(input logic [31:0] got, input logic [31:0] exp, input string msg);
        if (got !== exp) begin
            fail_count = fail_count + 1;
            $error("FAIL: %s expected=0x%08x got=0x%08x", msg, exp, got);
        end else begin
            pass_count = pass_count + 1;
        end
    endtask

    task automatic issue_i_read(
        input  logic [31:0] addr,
        output logic [31:0] rdata,
        output bit          err_seen
    );
        int timeout;
        bit got_done;
        begin
            i_req  <= 1'b1;
            i_addr <= addr;
            timeout = 0;
            got_done = 1'b0;
            while (!got_done && timeout < 40) begin
                @(posedge clk);
                #1;
                if (i_done) begin
                    got_done = 1'b1;
                end
                timeout = timeout + 1;
            end
            check_true(got_done, "I request completed");
            rdata = i_rdata;
            err_seen = i_err;

            i_req  <= 1'b0;
            i_addr <= 32'h0000_0000;
            @(posedge clk);
        end
    endtask

    task automatic issue_d_access(
        input  logic        we,
        input  logic [1:0]  size,
        input  logic [31:0] addr,
        input  logic [31:0] wdata,
        output logic [31:0] rdata,
        output bit          err_seen
    );
        int timeout;
        bit got_done;
        begin
            d_req   <= 1'b1;
            d_we    <= we;
            d_size  <= size;
            d_addr  <= addr;
            d_wdata <= wdata;
            timeout = 0;
            got_done = 1'b0;
            while (!got_done && timeout < 40) begin
                @(posedge clk);
                #1;
                if (d_done) begin
                    got_done = 1'b1;
                end
                timeout = timeout + 1;
            end
            check_true(got_done, "D request completed");
            rdata = d_rdata;
            err_seen = d_err;

            d_req   <= 1'b0;
            d_we    <= 1'b0;
            d_size  <= SIZE_WORD;
            d_addr  <= 32'h0000_0000;
            d_wdata <= 32'h0000_0000;
            @(posedge clk);
        end
    endtask

    initial begin
        logic [31:0] rd;
        bit          err_seen;
        int          timeout;

        clk = 1'b0;
        rst = 1'b1;
        uart_rx = 1'b1;

        i_req = 1'b0;
        i_addr = 32'h0;
        d_req = 1'b0;
        d_we = 1'b0;
        d_size = SIZE_WORD;
        d_addr = 32'h0;
        d_wdata = 32'h0;

        pass_count = 0;
        fail_count = 0;

        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_biu.vcd");
            $dumpvars(0, tb_biu);
        end

        repeat (4) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
        #1;

        issue_i_read(32'h0000_0000, rd, err_seen);
        check_true(!err_seen, "I read aligned address succeeds");
        check_eq32(rd, 32'h0000_0000, "I read default data is zero");

        issue_i_read(32'h0000_0002, rd, err_seen);
        check_true(err_seen, "I read misaligned address errors");

        issue_d_access(1'b1, SIZE_WORD, 32'h0000_0010, 32'h1122_3344, rd, err_seen);
        check_true(!err_seen, "D word write succeeds");
        issue_d_access(1'b0, SIZE_WORD, 32'h0000_0010, 32'h0, rd, err_seen);
        check_true(!err_seen, "D word read succeeds");
        check_eq32(rd, 32'h1122_3344, "D word readback matches");

        issue_d_access(1'b1, SIZE_BYTE, 32'h0000_0011, 32'h0000_00AA, rd, err_seen);
        check_true(!err_seen, "D byte write succeeds");
        issue_d_access(1'b0, SIZE_WORD, 32'h0000_0010, 32'h0, rd, err_seen);
        check_eq32(rd, 32'h11AA_3344, "D byte write updated correct lane");
        issue_d_access(1'b0, SIZE_BYTE, 32'h0000_0011, 32'h0, rd, err_seen);
        check_eq32(rd, 32'h0000_00AA, "D byte read extracts selected byte");

        issue_d_access(1'b1, SIZE_HALF, 32'h0000_0012, 32'h0000_BEEF, rd, err_seen);
        check_true(!err_seen, "D half write at offset 2 succeeds");
        issue_d_access(1'b0, SIZE_WORD, 32'h0000_0010, 32'h0, rd, err_seen);
        check_eq32(rd, 32'h11AA_BEEF, "D half write updated lower half");
        issue_d_access(1'b0, SIZE_HALF, 32'h0000_0012, 32'h0, rd, err_seen);
        check_eq32(rd, 32'h0000_BEEF, "D half read extracts selected half");

        issue_d_access(1'b0, SIZE_HALF, 32'h0000_0011, 32'h0, rd, err_seen);
        check_true(err_seen, "D half read misaligned errors");
        issue_d_access(1'b1, SIZE_WORD, 32'h0000_0012, 32'hA5A5_5A5A, rd, err_seen);
        check_true(err_seen, "D word write misaligned errors");

        issue_d_access(1'b0, SIZE_WORD, 32'h0001_0000, 32'h0, rd, err_seen);
        check_true(err_seen, "D read unmapped errors");

        // Concurrent request sanity: I and D can make progress independently.
        i_req   <= 1'b1;
        i_addr  <= 32'h0000_0010;
        d_req   <= 1'b1;
        d_we    <= 1'b0;
        d_size  <= SIZE_WORD;
        d_addr  <= 32'h0000_0010;
        d_wdata <= 32'h0;

        timeout = 0;
        while ((!i_done || !d_done) && timeout < 40) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end
        #1;
        check_true(timeout < 40, "Concurrent I/D requests complete");
        check_true(!i_err && !d_err, "Concurrent I/D requests are error free");
        check_eq32(i_rdata, 32'h11AA_BEEF, "Concurrent I read data");
        check_eq32(d_rdata, 32'h11AA_BEEF, "Concurrent D read data");

        i_req   <= 1'b0;
        i_addr  <= 32'h0;
        d_req   <= 1'b0;
        d_we    <= 1'b0;
        d_size  <= SIZE_WORD;
        d_addr  <= 32'h0;
        d_wdata <= 32'h0;
        @(posedge clk);

        $display("PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count != 0) begin
            $fatal(1, "tb_biu failed");
        end
        $finish;
    end
endmodule
