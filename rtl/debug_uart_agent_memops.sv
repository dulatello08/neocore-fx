module debug_uart_agent_memops #(
    parameter int unsigned MEM_TIMEOUT_CYCLES = 4096
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        start_i,
    input  logic        is_read_i,
    input  logic        is_burst_i,
    input  logic        burst_is_set_i,
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic [1:0]  size_i,
    input  logic [7:0]  burst_count_i,

    output logic        busy_o,
    output logic        done_valid_o,
    output logic [7:0]  done_status_o,
    output logic [7:0]  done_len_o,
    output logic [7:0]  done_payload_o [0:31],

    output logic        dbg_mem_req_o,
    output logic        dbg_mem_we_o,
    output logic [1:0]  dbg_mem_size_o,
    output logic [31:0] dbg_mem_addr_o,
    output logic [31:0] dbg_mem_wdata_o,
    input  logic        dbg_mem_done_i,
    input  logic [31:0] dbg_mem_rdata_i,
    input  logic        dbg_mem_err_i
);
    timeunit 1ns;
    timeprecision 1ps;

    import debug_uart_agent_pkg::*;

    logic [31:0] timeout_ctr_q;
    logic op_is_read_q;
    logic burst_active_q;
    logic burst_is_set_q;
    logic [7:0] burst_total_q;
    logic [7:0] burst_remaining_q;
    logic [7:0] burst_index_q;
    logic [31:0] burst_addr_q;
    logic [31:0] burst_value_q;
    integer i;

    assign busy_o = dbg_mem_req_o;

    task automatic emit_done(
        input logic [7:0] status,
        input logic [7:0] len
    );
        begin
            done_status_o <= status;
            done_len_o <= len;
            done_valid_o <= 1'b1;
            dbg_mem_req_o <= 1'b0;
        end
    endtask

    always_ff @(posedge clk) begin
        logic [31:0] stride_bytes;

        done_valid_o <= 1'b0;

        if (rst) begin
            timeout_ctr_q <= 32'h0000_0000;
            op_is_read_q <= 1'b0;
            burst_active_q <= 1'b0;
            burst_is_set_q <= 1'b0;
            burst_total_q <= 8'd0;
            burst_remaining_q <= 8'd0;
            burst_index_q <= 8'd0;
            burst_addr_q <= 32'h0000_0000;
            burst_value_q <= 32'h0000_0000;

            dbg_mem_req_o <= 1'b0;
            dbg_mem_we_o <= 1'b0;
            dbg_mem_size_o <= SIZE_WORD;
            dbg_mem_addr_o <= 32'h0000_0000;
            dbg_mem_wdata_o <= 32'h0000_0000;

            done_status_o <= ST_OK;
            done_len_o <= 8'd0;
            for (i = 0; i < 32; i = i + 1) begin
                done_payload_o[i] <= 8'h00;
            end
        end else begin
            if (start_i && !dbg_mem_req_o) begin
                timeout_ctr_q <= 32'h0000_0000;
                op_is_read_q <= is_read_i;
                burst_active_q <= is_burst_i;
                burst_is_set_q <= burst_is_set_i;
                burst_total_q <= burst_count_i;
                burst_remaining_q <= burst_count_i;
                burst_index_q <= 8'd0;
                burst_addr_q <= addr_i;
                burst_value_q <= wdata_i;

                dbg_mem_addr_o <= addr_i;
                dbg_mem_wdata_o <= wdata_i;
                dbg_mem_size_o <= size_i;
                dbg_mem_we_o <= is_burst_i ? burst_is_set_i : !is_read_i;
                dbg_mem_req_o <= 1'b1;
            end else if (dbg_mem_req_o) begin
                if (dbg_mem_done_i) begin
                    if (burst_active_q) begin
                        if (dbg_mem_err_i) begin
                            burst_active_q <= 1'b0;
                            emit_done(ST_BUS_ERR, 8'd0);
                        end else begin
                            if (!burst_is_set_q) begin
                                done_payload_o[(burst_index_q * 8'd4) + 8'd0] <= dbg_mem_rdata_i[31:24];
                                done_payload_o[(burst_index_q * 8'd4) + 8'd1] <= dbg_mem_rdata_i[23:16];
                                done_payload_o[(burst_index_q * 8'd4) + 8'd2] <= dbg_mem_rdata_i[15:8];
                                done_payload_o[(burst_index_q * 8'd4) + 8'd3] <= dbg_mem_rdata_i[7:0];
                            end

                            if (burst_remaining_q <= 8'd1) begin
                                burst_active_q <= 1'b0;
                                if (burst_is_set_q) begin
                                    emit_done(ST_OK, 8'd0);
                                end else begin
                                    emit_done(ST_OK, burst_total_q * 8'd4);
                                end
                            end else begin
                                stride_bytes = mem_stride_bytes(dbg_mem_size_o);
                                burst_addr_q <= burst_addr_q + stride_bytes;
                                burst_index_q <= burst_index_q + 8'd1;
                                burst_remaining_q <= burst_remaining_q - 8'd1;
                                dbg_mem_addr_o <= burst_addr_q + stride_bytes;
                                dbg_mem_wdata_o <= burst_value_q;
                                dbg_mem_we_o <= burst_is_set_q;
                                dbg_mem_req_o <= 1'b1;
                                timeout_ctr_q <= 32'h0000_0000;
                            end
                        end
                    end else if (dbg_mem_err_i) begin
                        emit_done(ST_BUS_ERR, 8'd0);
                    end else if (op_is_read_q) begin
                        done_payload_o[0] <= dbg_mem_rdata_i[31:24];
                        done_payload_o[1] <= dbg_mem_rdata_i[23:16];
                        done_payload_o[2] <= dbg_mem_rdata_i[15:8];
                        done_payload_o[3] <= dbg_mem_rdata_i[7:0];
                        emit_done(ST_OK, 8'd4);
                    end else begin
                        emit_done(ST_OK, 8'd0);
                    end
                end else if (timeout_ctr_q >= MEM_TIMEOUT_CYCLES) begin
                    burst_active_q <= 1'b0;
                    emit_done(ST_TIMEOUT, 8'd0);
                end else begin
                    timeout_ctr_q <= timeout_ctr_q + 32'd1;
                end
            end
        end
    end
endmodule : debug_uart_agent_memops
