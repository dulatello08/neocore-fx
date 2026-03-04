//
// regfile.sv
// NeoCoreFX - 16x32 register file (2R1W)
//

module regfile (
    // Clock/reset controls.
    input  logic        clk,
    input  logic        rst,

    // Read ports.
    input  logic [3:0]  rs1_addr_i,
    input  logic [3:0]  rs2_addr_i,
    output logic [31:0] rs1_data_o,
    output logic [31:0] rs2_data_o,

    // Write port.
    input  logic        we_i,
    input  logic [3:0]  waddr_i,
    input  logic [31:0] wdata_i
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [31:0] regs [0:15];

    integer idx;
    always_ff @(posedge clk) begin
        if (rst) begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                regs[idx] <= 32'h0000_0000;
            end
        end else if (we_i && (waddr_i != 4'h0)) begin
            regs[waddr_i] <= wdata_i;
        end
    end

    always_comb begin
        rs1_data_o = 32'h0000_0000;
        rs2_data_o = 32'h0000_0000;

        if (rs1_addr_i != 4'h0) begin
            if (we_i && (waddr_i == rs1_addr_i) && (waddr_i != 4'h0)) begin
                rs1_data_o = wdata_i;
            end else begin
                rs1_data_o = regs[rs1_addr_i];
            end
        end

        if (rs2_addr_i != 4'h0) begin
            if (we_i && (waddr_i == rs2_addr_i) && (waddr_i != 4'h0)) begin
                rs2_data_o = wdata_i;
            end else begin
                rs2_data_o = regs[rs2_addr_i];
            end
        end
    end
endmodule
