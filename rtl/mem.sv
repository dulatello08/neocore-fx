//
// mem.sv
// NeoCoreFX - Memory subsystem fabric (BRAM + MMIO UART)
//

module mem (
    // Clock/reset controls.
    input  logic        clk,
    input  logic        rst,

    // I-Bus read-only port.
    input  logic        ibus_cyc,
    input  logic        ibus_stb,
    input  logic [31:0] ibus_addr,
    output logic        ibus_ack,
    output logic [31:0] ibus_rdata,
    output logic        ibus_err,

    // D-Bus read/write port.
    input  logic        dbus_cyc,
    input  logic        dbus_stb,
    input  logic        dbus_we,
    input  logic [31:0] dbus_addr,
    input  logic [31:0] dbus_wdata,
    input  logic [3:0]  dbus_sel,
    output logic        dbus_ack,
    output logic [31:0] dbus_rdata,
    output logic        dbus_err,

    // SoC UART pins.
    input  logic        uart_rx_i,
    output logic        uart_tx_o
);
    timeunit 1ns;
    timeprecision 1ps;

    import mem_pkg::*;

    logic dbus_valid;
    logic d_sel_bram;
    logic d_sel_uart;
    logic d_decode_err;

    logic        bram_dbus_cyc;
    logic        bram_dbus_stb;
    logic        bram_dbus_ack;
    logic [31:0] bram_dbus_rdata;
    logic        bram_dbus_err;

    logic        uart_req;
    logic        uart_ack;
    logic [31:0] uart_rdata;
    logic        uart_err;

    logic d_decode_err_q;

    assign dbus_valid = dbus_cyc & dbus_stb;
    assign d_sel_bram = dbus_valid && mem_addr_in_range(dbus_addr);
    assign d_sel_uart = dbus_valid && uart_addr_in_range(dbus_addr);
    assign d_decode_err = dbus_valid && !d_sel_bram && !d_sel_uart;

    assign bram_dbus_cyc = d_sel_bram;
    assign bram_dbus_stb = d_sel_bram;
    assign uart_req = d_sel_uart;

    mem_bram u_bram (
        .clk        (clk),
        .rst        (rst),
        .ibus_cyc   (ibus_cyc),
        .ibus_stb   (ibus_stb),
        .ibus_addr  (ibus_addr),
        .ibus_ack   (ibus_ack),
        .ibus_rdata (ibus_rdata),
        .ibus_err   (ibus_err),
        .dbus_cyc   (bram_dbus_cyc),
        .dbus_stb   (bram_dbus_stb),
        .dbus_we    (dbus_we),
        .dbus_addr  (dbus_addr),
        .dbus_wdata (dbus_wdata),
        .dbus_sel   (dbus_sel),
        .dbus_ack   (bram_dbus_ack),
        .dbus_rdata (bram_dbus_rdata),
        .dbus_err   (bram_dbus_err)
    );

    uart_mmio u_uart (
        .clk        (clk),
        .rst        (rst),
        .req_i      (uart_req),
        .we_i       (dbus_we),
        .addr_i     (dbus_addr),
        .wdata_i    (dbus_wdata),
        .sel_i      (dbus_sel),
        .ack_o      (uart_ack),
        .rdata_o    (uart_rdata),
        .err_o      (uart_err),
        .uart_rx_i  (uart_rx_i),
        .uart_tx_o  (uart_tx_o)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            d_decode_err_q <= 1'b0;
        end else begin
            d_decode_err_q <= d_decode_err;
        end
    end

    // D-Bus response mux with one-cycle decode-error pulse.
    always_comb begin
        dbus_ack = 1'b0;
        dbus_err = 1'b0;
        dbus_rdata = 32'h0000_0000;

        if (bram_dbus_ack) begin
            dbus_ack = 1'b1;
            dbus_rdata = bram_dbus_rdata;
        end else if (uart_ack) begin
            dbus_ack = 1'b1;
            dbus_rdata = uart_rdata;
        end else if (bram_dbus_err || uart_err || d_decode_err_q) begin
            dbus_err = 1'b1;
        end
    end
endmodule : mem
