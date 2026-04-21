`timescale 1ns/1ps

module tb_debug_mmio;
    import mem_pkg::*;

    localparam int CLK_HALF_PERIOD_NS = 5;

    logic clk;
    logic rst;

    logic req;
    logic we;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [3:0] sel;
    logic ack;
    logic [31:0] rdata;
    logic err;

    logic core_halted;
    logic [2:0] core_halt_reason;
    logic [31:0] core_pc;
    logic core_last_fault;
    logic [31:0] core_last_fault_pc;
    logic [31:0] core_last_fault_addr;
    logic [31:0] core_last_illegal_inst;

    logic halt_req;
    logic resume_req;
    logic step_req;

    logic [3:0] gpr_addr;
    logic [31:0] gpr_rdata;
    logic gpr_we;
    logic [31:0] gpr_wdata;

    logic [31:0] cycle_count;
    logic [31:0] retire_count;
    logic [31:0] redirect_count;
    logic [31:0] load_stall_count;
    logic [31:0] mem_stall_count;

    logic dbg_mem_req;
    logic dbg_mem_we;
    logic [1:0] dbg_mem_size;
    logic [31:0] dbg_mem_addr;
    logic [31:0] dbg_mem_wdata;
    logic dbg_mem_done;
    logic [31:0] dbg_mem_rdata;
    logic dbg_mem_err;
    logic halt_seen;
    logic gpr_we_seen;

    int pass_count;
    int fail_count;

    debug_mmio dut (
        .clk                    (clk),
        .rst                    (rst),
        .req_i                  (req),
        .we_i                   (we),
        .addr_i                 (addr),
        .wdata_i                (wdata),
        .sel_i                  (sel),
        .ack_o                  (ack),
        .rdata_o                (rdata),
        .err_o                  (err),
        .core_halted_i          (core_halted),
        .core_halt_reason_i     (core_halt_reason),
        .core_pc_i              (core_pc),
        .core_last_fault_i      (core_last_fault),
        .core_last_fault_pc_i   (core_last_fault_pc),
        .core_last_fault_addr_i (core_last_fault_addr),
        .core_last_illegal_inst_i(core_last_illegal_inst),
        .halt_req_o             (halt_req),
        .resume_req_o           (resume_req),
        .step_req_o             (step_req),
        .gpr_addr_o             (gpr_addr),
        .gpr_rdata_i            (gpr_rdata),
        .gpr_we_o               (gpr_we),
        .gpr_wdata_o            (gpr_wdata),
        .cycle_count_i          (cycle_count),
        .retire_count_i         (retire_count),
        .branch_redirect_count_i(redirect_count),
        .load_stall_count_i     (load_stall_count),
        .mem_stall_count_i      (mem_stall_count),
        .dbg_mem_req_o          (dbg_mem_req),
        .dbg_mem_we_o           (dbg_mem_we),
        .dbg_mem_size_o         (dbg_mem_size),
        .dbg_mem_addr_o         (dbg_mem_addr),
        .dbg_mem_wdata_o        (dbg_mem_wdata),
        .dbg_mem_done_i         (dbg_mem_done),
        .dbg_mem_rdata_i        (dbg_mem_rdata),
        .dbg_mem_err_i          (dbg_mem_err)
    );

    always begin
        #(CLK_HALF_PERIOD_NS) clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            halt_seen <= 1'b0;
            gpr_we_seen <= 1'b0;
        end else begin
            if (halt_req) halt_seen <= 1'b1;
            if (gpr_we) gpr_we_seen <= 1'b1;
        end
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

    task automatic check_pulse_within_2_cycles(input logic sig, input string msg);
        bit seen;
        begin
            seen = sig;
            @(posedge clk);
            #1;
            seen = seen || sig;
            @(posedge clk);
            #1;
            seen = seen || sig;
            check_true(seen, msg);
        end
    endtask

    task automatic bus_write(input logic [31:0] a, input logic [31:0] d);
        begin
            req <= 1'b1;
            we <= 1'b1;
            addr <= a;
            wdata <= d;
            sel <= 4'b1111;
            @(posedge clk);
            req <= 1'b0;
            we <= 1'b0;
            addr <= 32'h0;
            wdata <= 32'h0;
            sel <= 4'b0000;
            @(posedge clk);
            #1;
            check_true(ack && !err, $sformatf("write ack @0x%08x", a));
        end
    endtask

    task automatic bus_read(input logic [31:0] a, output logic [31:0] d);
        begin
            req <= 1'b1;
            we <= 1'b0;
            addr <= a;
            wdata <= 32'h0;
            sel <= 4'b1111;
            @(posedge clk);
            req <= 1'b0;
            addr <= 32'h0;
            sel <= 4'b0000;
            @(posedge clk);
            #1;
            check_true(ack && !err, $sformatf("read ack @0x%08x", a));
            d = rdata;
        end
    endtask

    initial begin
        logic [31:0] rd;

        clk = 1'b0;
        rst = 1'b1;
        req = 1'b0;
        we = 1'b0;
        addr = 32'h0;
        wdata = 32'h0;
        sel = 4'b0000;

        core_halted = 1'b0;
        core_halt_reason = 3'b010;
        core_pc = 32'h0000_1234;
        core_last_fault = 1'b0;
        core_last_fault_pc = 32'h0000_0040;
        core_last_fault_addr = 32'h0000_2000;
        core_last_illegal_inst = 32'hF123_4567;

        gpr_rdata = 32'hDEAD_BEEF;

        cycle_count = 32'd100;
        retire_count = 32'd55;
        redirect_count = 32'd3;
        load_stall_count = 32'd7;
        mem_stall_count = 32'd11;

        dbg_mem_done = 1'b0;
        dbg_mem_rdata = 32'h0000_0000;
        dbg_mem_err = 1'b0;

        pass_count = 0;
        fail_count = 0;

        repeat (4) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
        #1;

        bus_read(DEBUG_BASE_ADDR + DEBUG_ID_OFFSET, rd);
        check_eq32(rd, 32'h4E43_4442, "DBG_ID matches");

        halt_seen = 1'b0;
        bus_write(DEBUG_BASE_ADDR + DEBUG_CTRL_OFFSET, 32'h0000_0001);
        repeat (2) @(posedge clk);
        #1;
        check_true(halt_seen, "halt request pulse");

        // GPR write is blocked when not halted.
        bus_write(DEBUG_BASE_ADDR + DEBUG_GPR_IDX_OFFSET, 32'h0000_0003);
        bus_write(DEBUG_BASE_ADDR + DEBUG_GPR_WDATA_OFFSET, 32'h1234_5678);
        bus_write(DEBUG_BASE_ADDR + DEBUG_GPR_CMD_OFFSET, 32'h0000_0002);
        #1;
        check_true(!gpr_we, "gpr write blocked while running");

        // Enable halted mode and repeat write.
        core_halted = 1'b1;
        @(posedge clk);
        gpr_we_seen = 1'b0;
        bus_write(DEBUG_BASE_ADDR + DEBUG_GPR_CMD_OFFSET, 32'h0000_0002);
        repeat (2) @(posedge clk);
        #1;
        check_true(gpr_we_seen, "gpr write allowed while halted");
        check_true(gpr_addr == 4'h3, "gpr index forwarded");
        check_eq32(gpr_wdata, 32'h1234_5678, "gpr data forwarded");

        // Launch debug memory read command and complete it.
        bus_write(DEBUG_BASE_ADDR + DEBUG_MEM_ADDR_OFFSET, 32'h0000_0100);
        bus_write(DEBUG_BASE_ADDR + DEBUG_MEM_CMD_OFFSET, 32'h0000_0001); // read, byte-size field ignored here

        repeat (3) @(posedge clk);
        check_true(dbg_mem_req, "dbg mem request asserted");
        check_true(!dbg_mem_we, "dbg mem read direction");
        check_eq32(dbg_mem_addr, 32'h0000_0100, "dbg mem addr forwarded");

        dbg_mem_rdata = 32'hAABB_CCDD;
        dbg_mem_done = 1'b1;
        @(posedge clk);
        dbg_mem_done = 1'b0;

        bus_read(DEBUG_BASE_ADDR + DEBUG_MEM_RDATA_OFFSET, rd);
        check_eq32(rd, 32'hAABB_CCDD, "dbg mem readback data latched");

        bus_read(DEBUG_BASE_ADDR + DEBUG_CYCLE_COUNT_OFFSET, rd);
        check_eq32(rd, 32'd100, "cycle counter mirrored");

        $display("PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count != 0) begin
            $fatal(1, "tb_debug_mmio failed");
        end
        $finish;
    end
endmodule
