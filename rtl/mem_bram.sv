//
// mem_bram.sv
// NeoCoreFX - BRAM slave for instruction/data buses
//

module mem_bram (
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
    output logic        dbus_err
);
    timeunit 1ns;
    timeprecision 1ps;

    import mem_pkg::*;

    localparam int unsigned BANKS = 4;
    localparam int unsigned BANK_DEPTH = MEM_WORDS / BANKS;
    localparam int unsigned BANK_ADDR_W = $clog2(BANK_DEPTH);

    // -------------------------------------------------------------------------
    // Address decode
    // -------------------------------------------------------------------------
    logic ibus_valid;
    logic dbus_valid;
    logic ibus_in_range;
    logic dbus_in_range;
    logic ibus_aligned;

    logic [13:0] ibus_word_idx;
    logic [13:0] dbus_word_idx;
    logic [1:0]  ibus_bank_sel;
    logic [1:0]  dbus_bank_sel;
    logic [BANK_ADDR_W-1:0] ibus_row_addr;
    logic [BANK_ADDR_W-1:0] dbus_row_addr;

    assign ibus_valid    = ibus_cyc & ibus_stb;
    assign dbus_valid    = dbus_cyc & dbus_stb;
    assign ibus_in_range = mem_addr_in_range(ibus_addr);
    assign dbus_in_range = mem_addr_in_range(dbus_addr);
    assign ibus_aligned  = (ibus_addr[1:0] == 2'b00);

    assign ibus_word_idx = mem_word_index(ibus_addr);
    assign dbus_word_idx = mem_word_index(dbus_addr);

    assign ibus_bank_sel = ibus_word_idx[1:0];
    assign dbus_bank_sel = dbus_word_idx[1:0];
    assign ibus_row_addr = ibus_word_idx[13:2];
    assign dbus_row_addr = dbus_word_idx[13:2];

    // -------------------------------------------------------------------------
    // BRAM banks
    // Mirrors cpu-private structure: each bank is a true dual-port 32-bit RAM.
    // -------------------------------------------------------------------------
    logic [31:0] ibus_bank_rdata [0:BANKS-1];
    logic [31:0] dbus_bank_rdata [0:BANKS-1];
    logic [1:0]  ibus_bank_sel_reg;
    logic [1:0]  dbus_bank_sel_reg;

    generate
        for (genvar i = 0; i < BANKS; i++) begin : bank_gen
            (* ram_style = "block" *) logic [31:0] mem [0:BANK_DEPTH-1];
            logic [31:0] rdata_a;
            logic [31:0] rdata_b;
            logic        dbus_hit_bank;

            assign dbus_hit_bank = dbus_valid && dbus_in_range && dbus_we && (dbus_bank_sel == i[1:0]);

            // Port A: instruction fetch (read-only)
            always_ff @(posedge clk) begin
                rdata_a <= mem[ibus_row_addr];
            end

            // Port B: data access (read/write with byte-lane enables)
            always_ff @(posedge clk) begin
                if (dbus_hit_bank && dbus_sel[3]) mem[dbus_row_addr][31:24] <= dbus_wdata[31:24];
                if (dbus_hit_bank && dbus_sel[2]) mem[dbus_row_addr][23:16] <= dbus_wdata[23:16];
                if (dbus_hit_bank && dbus_sel[1]) mem[dbus_row_addr][15:8]  <= dbus_wdata[15:8];
                if (dbus_hit_bank && dbus_sel[0]) mem[dbus_row_addr][7:0]   <= dbus_wdata[7:0];
                rdata_b <= mem[dbus_row_addr];
            end

            assign ibus_bank_rdata[i] = rdata_a;
            assign dbus_bank_rdata[i] = rdata_b;

            initial begin : init_bank_mem
`ifdef SYNTHESIS
  `ifdef MEM_INIT_HEX_BANK0
                // Yosys ignores $readmemh after a for-loop, so skip zero-init
                // when bank init data is provided.
  `else
                int unsigned j;
                for (j = 0; j < BANK_DEPTH; j = j + 1) begin
                    mem[j] = 32'h0000_0000;
                end
  `endif
`else
                int unsigned j;
                for (j = 0; j < BANK_DEPTH; j = j + 1) begin
                    mem[j] = 32'h0000_0000;
                end
`endif
`ifdef MEM_INIT_HEX_BANK0
                if (i == 0) begin
                    $readmemh(`MEM_INIT_HEX_BANK0, mem);
                end
`endif
`ifdef MEM_INIT_HEX_BANK1
                if (i == 1) begin
                    $readmemh(`MEM_INIT_HEX_BANK1, mem);
                end
`endif
`ifdef MEM_INIT_HEX_BANK2
                if (i == 2) begin
                    $readmemh(`MEM_INIT_HEX_BANK2, mem);
                end
`endif
`ifdef MEM_INIT_HEX_BANK3
                if (i == 3) begin
                    $readmemh(`MEM_INIT_HEX_BANK3, mem);
                end
`endif
            end
        end
    endgenerate

    assign ibus_rdata = ibus_bank_rdata[ibus_bank_sel_reg];
    assign dbus_rdata = dbus_bank_rdata[dbus_bank_sel_reg];

    // -------------------------------------------------------------------------
    // Request/response pipelining
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            ibus_ack          <= 1'b0;
            ibus_err          <= 1'b0;
            ibus_bank_sel_reg <= 2'b00;
            dbus_ack          <= 1'b0;
            dbus_err          <= 1'b0;
            dbus_bank_sel_reg <= 2'b00;
        end else begin
            ibus_ack <= ibus_valid && ibus_in_range && ibus_aligned;
            ibus_err <= ibus_valid && (!ibus_in_range || !ibus_aligned);
            if (ibus_valid && ibus_in_range && ibus_aligned) begin
                ibus_bank_sel_reg <= ibus_bank_sel;
            end

            dbus_ack <= dbus_valid && dbus_in_range;
            dbus_err <= dbus_valid && !dbus_in_range;
            if (dbus_valid && dbus_in_range) begin
                dbus_bank_sel_reg <= dbus_bank_sel;
            end
        end
    end
endmodule : mem_bram
