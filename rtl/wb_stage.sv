//
// wb_stage.sv
// NeoCoreFX - WB (register write control)
//

module wb_stage (
    // MEM -> WB pipeline inputs.
    input  logic        memwb_valid_i,
    input  logic [3:0]  memwb_rd_i,
    input  logic        memwb_reg_write_i,
    input  logic [31:0] memwb_data_i,
    input  logic        memwb_mem_fault_i,
    input  logic        memwb_fetch_fault_i,
    input  logic        memwb_illegal_i,

    // Register file write port.
    output logic        rf_we_o,
    output logic [3:0]  rf_waddr_o,
    output logic [31:0] rf_wdata_o,

    // Writeback status outputs.
    output logic        wb_valid_o,
    output logic        wb_fault_o
);
    timeunit 1ns;
    timeprecision 1ps;

    logic kill_write;

    always_comb begin
        kill_write = memwb_mem_fault_i || memwb_fetch_fault_i || memwb_illegal_i;

        rf_we_o = memwb_valid_i && memwb_reg_write_i && !kill_write && (memwb_rd_i != 4'h0);
        rf_waddr_o = memwb_rd_i;
        rf_wdata_o = memwb_data_i;

        wb_valid_o = memwb_valid_i;
        wb_fault_o = memwb_valid_i && kill_write;
    end
endmodule
