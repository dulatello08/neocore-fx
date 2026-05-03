`timescale 1ns/1ps

module tb_mem_nodebug;
    import mem_pkg::*;

    logic clk;
    logic rst;
    logic ibus_cyc;
    logic ibus_stb;
    logic [31:0] ibus_addr;
    logic ibus_ack;
    logic [31:0] ibus_rdata;
    logic ibus_err;
    logic dbus_cyc;
    logic dbus_stb;
    logic dbus_we;
    logic [31:0] dbus_addr;
    logic [31:0] dbus_wdata;
    logic [3:0] dbus_sel;
    logic dbus_ack;
    logic [31:0] dbus_rdata;
    logic dbus_err;
    logic dbg_halt_req;
    logic dbg_resume_req;
    logic dbg_step_req;
    logic dbg_pc_set_req;
    logic [31:0] dbg_pc_set_data;
    logic [3:0] dbg_gpr_addr;
    logic dbg_gpr_we;
    logic [31:0] dbg_gpr_wdata;
    logic uart_rx;
    logic uart_tx;
    int errors;

    mem #(
        .INCLUDE_DEBUG(1'b0)
    ) dut (
        .clk(clk),
        .rst(rst),
        .ibus_cyc(ibus_cyc),
        .ibus_stb(ibus_stb),
        .ibus_addr(ibus_addr),
        .ibus_ack(ibus_ack),
        .ibus_rdata(ibus_rdata),
        .ibus_err(ibus_err),
        .dbus_cyc(dbus_cyc),
        .dbus_stb(dbus_stb),
        .dbus_we(dbus_we),
        .dbus_addr(dbus_addr),
        .dbus_wdata(dbus_wdata),
        .dbus_sel(dbus_sel),
        .dbus_ack(dbus_ack),
        .dbus_rdata(dbus_rdata),
        .dbus_err(dbus_err),
        .debug_enable_i(1'b0),
        .core_halted_i(1'b1),
        .core_current_pc_i(32'h1234_5678),
        .core_halt_reason_i(3'h7),
        .core_last_fault_i(1'b1),
        .core_last_fault_pc_i(32'h1111_2222),
        .core_last_fault_addr_i(32'h3333_4444),
        .core_last_illegal_inst_i(32'h5555_6666),
        .core_cycle_count_i(32'hAAAA_0001),
        .core_retire_count_i(32'hAAAA_0002),
        .core_redirect_count_i(32'hAAAA_0003),
        .core_load_stall_count_i(32'hAAAA_0004),
        .core_mem_stall_count_i(32'hAAAA_0005),
        .dbg_halt_req_o(dbg_halt_req),
        .dbg_resume_req_o(dbg_resume_req),
        .dbg_step_req_o(dbg_step_req),
        .dbg_pc_set_req_o(dbg_pc_set_req),
        .dbg_pc_set_data_o(dbg_pc_set_data),
        .dbg_gpr_addr_o(dbg_gpr_addr),
        .dbg_gpr_rdata_i(32'hDEAD_BEEF),
        .dbg_gpr_we_o(dbg_gpr_we),
        .dbg_gpr_wdata_o(dbg_gpr_wdata),
        .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check(input logic cond, input string msg);
        if (!cond) begin
            $display("FAIL: %s", msg);
            errors++;
        end else begin
            $display("PASS: %s", msg);
        end
    endtask

    task automatic dbus_xact(
        input logic we,
        input logic [31:0] addr,
        input logic [31:0] wdata,
        output logic [31:0] rdata,
        output logic ack,
        output logic err
    );
        int cycles;
        begin
            rdata = 32'h0000_0000;
            ack = 1'b0;
            err = 1'b0;
            @(posedge clk);
            dbus_cyc <= 1'b1;
            dbus_stb <= 1'b1;
            dbus_we <= we;
            dbus_addr <= addr;
            dbus_wdata <= wdata;
            dbus_sel <= 4'b1111;
            for (cycles = 0; cycles < 32; cycles++) begin
                @(posedge clk);
                if (dbus_ack || dbus_err) begin
                    ack = dbus_ack;
                    err = dbus_err;
                    rdata = dbus_rdata;
                    cycles = 32;
                end
            end
            dbus_cyc <= 1'b0;
            dbus_stb <= 1'b0;
            dbus_we <= 1'b0;
            dbus_addr <= 32'h0000_0000;
            dbus_wdata <= 32'h0000_0000;
            dbus_sel <= 4'b0000;
            @(posedge clk);
        end
    endtask

    initial begin
        logic [31:0] rd;
        logic ack_seen;
        logic err_seen;

        errors = 0;
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

        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        check(!dbg_halt_req && !dbg_resume_req && !dbg_step_req, "debug requests are tied inactive");
        check(!dbg_pc_set_req && dbg_pc_set_data == 32'h0000_0000, "debug PC set is tied inactive");
        check(!dbg_gpr_we && dbg_gpr_addr == 4'h0 && dbg_gpr_wdata == 32'h0000_0000, "debug GPR write is tied inactive");

        dbus_xact(1'b0, DEBUG_BASE_ADDR, 32'h0000_0000, rd, ack_seen, err_seen);
        check(!ack_seen && err_seen, "debug MMIO address is unmapped");

        dbus_xact(1'b1, UART_BASE_ADDR + UART_CTRL_OFFSET, 32'h0000_0001, rd, ack_seen, err_seen);
        check(ack_seen && !err_seen, "direct UART CTRL write acks");
        dbus_xact(1'b1, UART_BASE_ADDR + UART_BAUDDIV_OFFSET, 32'h0000_0027, rd, ack_seen, err_seen);
        check(ack_seen && !err_seen, "direct UART BAUDDIV write acks");
        dbus_xact(1'b0, UART_BASE_ADDR + UART_BAUDDIV_OFFSET, 32'h0000_0000, rd, ack_seen, err_seen);
        check(ack_seen && !err_seen && rd == 32'h0000_0027, "direct UART BAUDDIV is firmware-visible");

        if (errors != 0) begin
            $fatal(1, "tb_mem_nodebug failed with %0d errors", errors);
        end
        $display("tb_mem_nodebug passed");
        $finish;
    end
endmodule : tb_mem_nodebug
