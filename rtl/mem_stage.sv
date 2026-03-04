//
// mem_stage.sv
// NeoCoreFX - MEM (D-port transaction + MEM/WB register + halt propagation)
//

module mem_stage
  import core_pkg::*;
(
    // Clock/reset and pipeline control.
    input  logic        clk,
    input  logic        rst,
    input  logic        stall_i,
    input  logic        flush_i,

    // EXE -> MEM pipeline inputs.
    input  logic        exe_valid_i,
    input  logic [3:0]  exe_rd_i,
    input  logic [3:0]  exe_store_rs2_addr_i,
    input  logic        exe_reg_write_i,
    input  logic        exe_mem_read_i,
    input  logic        exe_mem_write_i,
    input  logic [1:0]  exe_mem_size_i,
    input  logic        exe_load_sign_ext_i,
    input  logic [31:0] exe_result_i,
    input  logic [31:0] exe_store_data_i,
    input  logic        exe_fetch_fault_i,
    input  logic        exe_illegal_i,
    // Halt metadata from EXE stage.
    input  logic        exe_is_halt_i,

    // WB forwarding for store-data hazards.
    input  logic        wb_fwd_valid_i,
    input  logic [3:0]  wb_fwd_rd_i,
    input  logic [31:0] wb_fwd_data_i,

    // BIU D-port response.
    input  logic        d_done_i,
    input  logic [31:0] d_rdata_i,
    input  logic        d_err_i,

    // BIU D-port request.
    output logic        d_req_o,
    output logic        d_we_o,
    output logic [1:0]  d_size_o,
    output logic [31:0] d_addr_o,
    output logic [31:0] d_wdata_o,

    // Pipeline stall request while memory transaction is pending.
    output logic        stall_req_o,

    // MEM -> WB pipeline outputs.
    output logic        memwb_valid_o,
    output logic [3:0]  memwb_rd_o,
    output logic        memwb_reg_write_o,
    output logic [31:0] memwb_data_o,
    output logic        memwb_mem_fault_o,
    output logic        memwb_fetch_fault_o,
    output logic        memwb_illegal_o,
    // Halt metadata into WB stage.
    output logic        memwb_is_halt_o
);
    timeunit 1ns;
    timeprecision 1ps;

    logic        pending_q;
    logic        pend_valid_q;
    logic [3:0]  pend_rd_q;
    logic        pend_reg_write_q;
    logic        pend_mem_read_q;
    logic [1:0]  pend_mem_size_q;
    logic        pend_load_sign_ext_q;
    logic [31:0] pend_addr_q;
    logic [31:0] pend_store_data_q;
    logic [31:0] pend_result_q;
    logic        pend_fetch_fault_q;
    logic        pend_illegal_q;
    logic        pend_is_halt_q;

    logic        launch_req;
    logic [31:0] launch_store_data;

    logic        xact_valid;
    logic        xact_we;
    logic [1:0]  xact_size;
    logic [31:0] xact_addr;
    logic [31:0] xact_store_data;

    function automatic logic [31:0] load_extract(
        input logic [31:0] word_data,
        input logic [1:0]  size,
        input logic [1:0]  addr_lsb,
        input logic        sign_ext
    );
        logic [7:0]  b;
        logic [15:0] h;
        begin
            case (size)
                SIZE_BYTE: begin
                    case (addr_lsb)
                        2'b00: b = word_data[31:24];
                        2'b01: b = word_data[23:16];
                        2'b10: b = word_data[15:8];
                        default: b = word_data[7:0];
                    endcase
                    if (sign_ext) begin
                        load_extract = {{24{b[7]}}, b};
                    end else begin
                        load_extract = {24'h000000, b};
                    end
                end

                SIZE_HALF: begin
                    case (addr_lsb)
                        2'b00: h = word_data[31:16];
                        default: h = word_data[15:0];
                    endcase
                    if (sign_ext) begin
                        load_extract = {{16{h[15]}}, h};
                    end else begin
                        load_extract = {16'h0000, h};
                    end
                end

                default: begin
                    load_extract = word_data;
                end
            endcase
        end
    endfunction

    assign launch_store_data = (exe_mem_write_i
                             && wb_fwd_valid_i
                             && (wb_fwd_rd_i != 4'h0)
                             && (wb_fwd_rd_i == exe_store_rs2_addr_i))
                             ? wb_fwd_data_i
                             : exe_store_data_i;

    assign launch_req = exe_valid_i
                     && (exe_mem_read_i || exe_mem_write_i)
                     && !pending_q
                     && !flush_i;

    always_comb begin
        if (pending_q) begin
            xact_valid = 1'b1;
            xact_we = !pend_mem_read_q;
            xact_size = pend_mem_size_q;
            xact_addr = pend_addr_q;
            xact_store_data = pend_store_data_q;
        end else if (launch_req) begin
            xact_valid = 1'b1;
            xact_we = exe_mem_write_i;
            xact_size = exe_mem_size_i;
            xact_addr = exe_result_i;
            xact_store_data = launch_store_data;
        end else begin
            xact_valid = 1'b0;
            xact_we = 1'b0;
            xact_size = SIZE_WORD;
            xact_addr = 32'h0000_0000;
            xact_store_data = 32'h0000_0000;
        end
    end

    assign d_req_o = xact_valid;
    assign d_we_o = xact_we;
    assign d_size_o = xact_size;
    assign d_addr_o = xact_addr;
    assign d_wdata_o = xact_store_data;

    assign stall_req_o = xact_valid && !d_done_i;

    always_ff @(posedge clk) begin
        if (rst) begin
            pending_q            <= 1'b0;
            pend_valid_q         <= 1'b0;
            pend_rd_q            <= 4'h0;
            pend_reg_write_q     <= 1'b0;
            pend_mem_read_q      <= 1'b0;
            pend_mem_size_q      <= SIZE_WORD;
            pend_load_sign_ext_q <= 1'b0;
            pend_addr_q          <= 32'h0000_0000;
            pend_store_data_q    <= 32'h0000_0000;
            pend_result_q        <= 32'h0000_0000;
            pend_fetch_fault_q   <= 1'b0;
            pend_illegal_q       <= 1'b0;
            pend_is_halt_q       <= 1'b0;

            memwb_valid_o        <= 1'b0;
            memwb_rd_o           <= 4'h0;
            memwb_reg_write_o    <= 1'b0;
            memwb_data_o         <= 32'h0000_0000;
            memwb_mem_fault_o    <= 1'b0;
            memwb_fetch_fault_o  <= 1'b0;
            memwb_illegal_o      <= 1'b0;
            memwb_is_halt_o      <= 1'b0;
        end else if (flush_i) begin
            pending_q            <= 1'b0;
            pend_valid_q         <= 1'b0;
            pend_is_halt_q       <= 1'b0;

            memwb_valid_o        <= 1'b0;
            memwb_rd_o           <= 4'h0;
            memwb_reg_write_o    <= 1'b0;
            memwb_data_o         <= 32'h0000_0000;
            memwb_mem_fault_o    <= 1'b0;
            memwb_fetch_fault_o  <= 1'b0;
            memwb_illegal_o      <= 1'b0;
            memwb_is_halt_o      <= 1'b0;
        end else begin
            memwb_valid_o       <= 1'b0;
            memwb_mem_fault_o   <= 1'b0;
            memwb_fetch_fault_o <= 1'b0;
            memwb_illegal_o     <= 1'b0;
            memwb_is_halt_o     <= 1'b0;

            if (pending_q) begin
                if (d_done_i) begin
                    pending_q            <= 1'b0;
                    memwb_valid_o        <= pend_valid_q;
                    memwb_rd_o           <= pend_rd_q;
                    memwb_reg_write_o    <= pend_reg_write_q;
                    memwb_data_o         <= pend_mem_read_q
                                           ? load_extract(d_rdata_i, pend_mem_size_q,
                                                          pend_addr_q[1:0],
                                                          pend_load_sign_ext_q)
                                           : pend_result_q;
                    memwb_mem_fault_o    <= d_err_i;
                    memwb_fetch_fault_o  <= pend_fetch_fault_q;
                    memwb_illegal_o      <= pend_illegal_q;
                    memwb_is_halt_o      <= pend_is_halt_q;
                end
            end else if (launch_req) begin
                if (d_done_i) begin
                    memwb_valid_o        <= exe_valid_i;
                    memwb_rd_o           <= exe_rd_i;
                    memwb_reg_write_o    <= exe_reg_write_i;
                    memwb_data_o         <= exe_mem_read_i
                                           ? load_extract(d_rdata_i, exe_mem_size_i,
                                                          exe_result_i[1:0],
                                                          exe_load_sign_ext_i)
                                           : exe_result_i;
                    memwb_mem_fault_o    <= d_err_i;
                    memwb_fetch_fault_o  <= exe_fetch_fault_i;
                    memwb_illegal_o      <= exe_illegal_i;
                    memwb_is_halt_o      <= exe_is_halt_i;
                end else begin
                    pending_q            <= 1'b1;
                    pend_valid_q         <= exe_valid_i;
                    pend_rd_q            <= exe_rd_i;
                    pend_reg_write_q     <= exe_reg_write_i;
                    pend_mem_read_q      <= exe_mem_read_i;
                    pend_mem_size_q      <= exe_mem_size_i;
                    pend_load_sign_ext_q <= exe_load_sign_ext_i;
                    pend_addr_q          <= exe_result_i;
                    pend_store_data_q    <= launch_store_data;
                    pend_result_q        <= exe_result_i;
                    pend_fetch_fault_q   <= exe_fetch_fault_i;
                    pend_illegal_q       <= exe_illegal_i;
                    pend_is_halt_q       <= exe_is_halt_i;
                end
            end else if (!stall_i) begin
                memwb_valid_o       <= exe_valid_i;
                memwb_rd_o          <= exe_rd_i;
                memwb_reg_write_o   <= exe_reg_write_i;
                memwb_data_o        <= exe_result_i;
                memwb_mem_fault_o   <= 1'b0;
                memwb_fetch_fault_o <= exe_fetch_fault_i;
                memwb_illegal_o     <= exe_illegal_i;
                memwb_is_halt_o     <= exe_is_halt_i;
            end
        end
    end
endmodule
