module ncfx_mem (
    input  logic        clk,
    input  logic        rst_n,

    // I-Bus (read-only)
    input  logic        ibus_cyc,
    input  logic        ibus_stb,
    input  logic [31:0] ibus_addr,
    output logic        ibus_ack,
    output logic [31:0] ibus_rdata,
    output logic        ibus_err,

    // D-Bus (read/write)
    input  logic        dbus_cyc,
    input  logic        dbus_stb,
    input  logic        dbus_we,
    input  logic [31:0] dbus_addr,
    input  logic [31:0] dbus_wdata,
    input  logic [3:0]  dbus_sel,
    output logic        dbus_ack,
    output logic [31:0] dbus_rdata,
    output logic        dbus_err
);
    timeunit 1ns;
    timeprecision 1ps;

    import ncfx_mem_pkg::*;

    logic [31:0] mem [0:NCFX_MEM_WORDS-1];

    initial begin : init_mem
        int unsigned i;
        for (i = 0; i < NCFX_MEM_WORDS; i = i + 1) begin
            mem[i] = 32'h0000_0000;
        end
    end

    // -------------------------------------------------------------------------
    // I-Bus: 1-cycle pipelined BRAM read (address in → data out, 1 clock)
    // -------------------------------------------------------------------------
    logic ibus_valid;
    assign ibus_valid = ibus_cyc & ibus_stb;

    logic ibus_in_range;
    logic ibus_aligned;
    assign ibus_in_range = ncfx_mem_addr_in_range(ibus_addr);
    assign ibus_aligned  = (ibus_addr[1:0] == 2'b00);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ibus_ack   <= 1'b0;
            ibus_err   <= 1'b0;
            ibus_rdata <= 32'h0000_0000;
        end else begin
            ibus_rdata <= mem[ncfx_mem_word_index(ibus_addr)];
            ibus_ack   <= ibus_valid & ibus_in_range & ibus_aligned;
            ibus_err   <= ibus_valid & (~ibus_in_range | ~ibus_aligned);
        end
    end

    // -------------------------------------------------------------------------
    // D-Bus: 1-cycle pipelined BRAM read/write
    // Writes: combinational addr/data/sel merged into BRAM on posedge
    // Reads:  data out one cycle after addr presented
    // -------------------------------------------------------------------------
    logic dbus_valid;
    assign dbus_valid = dbus_cyc & dbus_stb;

    logic dbus_in_range;
    assign dbus_in_range = ncfx_mem_addr_in_range(dbus_addr);

    logic [13:0] dbus_word_idx;
    assign dbus_word_idx = ncfx_mem_word_index(dbus_addr);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbus_ack   <= 1'b0;
            dbus_err   <= 1'b0;
            dbus_rdata <= 32'h0000_0000;
        end else begin
            // Write path: apply byte-lane merge on posedge
            if (dbus_valid && dbus_in_range && dbus_we && (dbus_sel != 4'b0000)) begin
                mem[dbus_word_idx] <= ncfx_mem_apply_write_sel(
                    mem[dbus_word_idx],
                    dbus_wdata,
                    dbus_sel
                );
            end

            // Read path: always register the word at the addressed location
            dbus_rdata <= mem[dbus_word_idx];

            // Ack/err
            dbus_ack <= dbus_valid & dbus_in_range;
            dbus_err <= dbus_valid & ~dbus_in_range;
        end
    end
endmodule
