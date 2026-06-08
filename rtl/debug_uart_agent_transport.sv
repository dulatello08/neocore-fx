module debug_uart_agent_transport (
    input  logic       clk,
    input  logic       rst,
    output logic       uart_req_o,
    output logic       uart_we_o,
    output logic [31:0] uart_addr_o,
    output logic [31:0] uart_wdata_o,
    output logic [3:0]  uart_sel_o,
    input  logic       uart_ack_i,
    input  logic [31:0] uart_rdata_i,
    input  logic       uart_err_i,
    output logic       fw_rx_valid_o,
    output logic [7:0] fw_rx_data_o,
    input  logic       fw_rx_ready_i,
    input  logic       fw_tx_valid_i,
    input  logic [7:0] fw_tx_data_i,
    output logic       fw_tx_ready_o,
    output logic       cmd_valid_o,
    output logic [7:0] cmd_seq_o,
    output logic [7:0] cmd_id_o,
    output logic [7:0] cmd_len_o,
    output logic [7:0] cmd_payload_o [0:31],
    input  logic       cmd_ready_i,
    input  logic       resp_valid_i,
    input  logic [7:0] resp_seq_i,
    input  logic [7:0] resp_status_i,
    input  logic [7:0] resp_len_i,
    input  logic [7:0] resp_payload_i [0:31],
    input  logic       exec_busy_i,
    output logic       debug_active_o
);
    timeunit 1ns;
    timeprecision 1ps;
    import mem_pkg::*;
    import debug_uart_agent_pkg::*;
    transport_state_t state_q;
    logic [7:0] tx_buf [0:31];
    logic [7:0] tx_payload_len_q;
    logic [7:0] tx_idx_q;
    logic tx_active_q;
    logic [7:0] tx_seq_q;
    logic [7:0] tx_status_q;
    logic [15:0] tx_crc_q;
    logic [7:0] tx_byte_q;
    logic tx_crc_update_q;
    logic tx_from_fw_q;
    rx_state_t rx_state_q;
    logic [7:0] rx_seq_q;
    logic [7:0] rx_cmd_q;
    logic [7:0] rx_len_q;
    logic [7:0] rx_payload [0:31];
    logic [5:0] rx_payload_idx_q;
    logic [15:0] rx_crc_calc_q;
    logic [15:0] rx_crc_recv_q;
    logic [7:0] rx_frame_buf [0:RX_FRAME_MAX-1];
    logic [5:0] rx_frame_count_q;
    logic [5:0] flush_idx_q;
    logic [5:0] flush_count_q;
    logic frame_ready_q;
    logic frame_crc_ok_q;
    logic cmd_sent_q;
    logic [FW_RX_PTR_W-1:0] fw_rx_wr_ptr_q;
    logic [FW_RX_PTR_W-1:0] fw_rx_rd_ptr_q;
    logic [FW_RX_COUNT_W-1:0] fw_rx_count_q;
    integer i;
    task automatic parser_reset;
        begin
            rx_state_q <= RX_WAIT_SOF;
            rx_seq_q <= 8'h00;
            rx_cmd_q <= 8'h00;
            rx_len_q <= 8'h00;
            rx_payload_idx_q <= 6'd0;
            rx_crc_calc_q <= 16'hFFFF;
            rx_crc_recv_q <= 16'h0000;
            rx_frame_count_q <= 6'd0;
        end
    endtask
    logic [7:0] fw_rx_fifo [0:FW_RX_FIFO_DEPTH-1];
    assign fw_rx_valid_o = (fw_rx_count_q != 0);
    assign fw_rx_data_o = (fw_rx_count_q != 0) ? fw_rx_fifo[fw_rx_rd_ptr_q] : 8'h00;
    assign fw_tx_ready_o = (state_q == TS_POLL_STATUS_WAIT)
                        && uart_ack_i
                        && !uart_err_i
                        && uart_rdata_i[0]
                        && !uart_rdata_i[1]
                        && !tx_active_q;
    assign cmd_valid_o = (state_q == TS_PROCESS_CMD) && frame_ready_q && frame_crc_ok_q && !cmd_sent_q;
    assign debug_active_o = frame_ready_q
                         || (state_q == TS_PROCESS_CMD)
                         || (state_q == TS_FLUSH_FRAME)
                         || exec_busy_i;
    always_ff @(posedge clk) begin
        logic [7:0] rx_byte;
        logic [31:0] status_word;
        logic [7:0] tx_byte_sel;
        logic tx_crc_update_sel;
        logic [FW_RX_PTR_W-1:0] fw_rx_wr_ptr_n;
        logic [FW_RX_PTR_W-1:0] fw_rx_rd_ptr_n;
        logic [FW_RX_COUNT_W-1:0] fw_rx_count_n;
        if (rst) begin
            uart_req_o <= 1'b0;
            uart_we_o <= 1'b0;
            uart_addr_o <= 32'h0000_0000;
            uart_wdata_o <= 32'h0000_0000;
            uart_sel_o <= 4'b1111;
            tx_payload_len_q <= 8'd0;
            tx_idx_q <= 8'd0;
            tx_active_q <= 1'b0;
            tx_seq_q <= 8'h00;
            tx_status_q <= 8'h00;
            tx_crc_q <= 16'hFFFF;
            tx_byte_q <= 8'h00;
            tx_crc_update_q <= 1'b0;
            tx_from_fw_q <= 1'b0;
            parser_reset();
            frame_ready_q <= 1'b0;
            frame_crc_ok_q <= 1'b0;
            cmd_sent_q <= 1'b0;
            cmd_seq_o <= 8'h00;
            cmd_id_o <= 8'h00;
            cmd_len_o <= 8'h00;
            for (i = 0; i < 32; i = i + 1) begin
                cmd_payload_o[i] <= 8'h00;
            end
            fw_rx_wr_ptr_q <= '0;
            fw_rx_rd_ptr_q <= '0;
            fw_rx_count_q <= '0;
            flush_idx_q <= 6'd0;
            flush_count_q <= 6'd0;
            state_q <= TS_POLL_STATUS_REQ;
        end else begin
            fw_rx_wr_ptr_n = fw_rx_wr_ptr_q;
            fw_rx_rd_ptr_n = fw_rx_rd_ptr_q;
            fw_rx_count_n = fw_rx_count_q;
            if ((fw_rx_count_n != 0) && fw_rx_ready_i) begin
                fw_rx_rd_ptr_n = fw_rx_rd_ptr_n + 1'b1;
                fw_rx_count_n = fw_rx_count_n - 1'b1;
            end
            case (state_q)
                TS_POLL_STATUS_REQ: begin
                    uart_req_o <= 1'b1;
                    uart_we_o <= 1'b0;
                    uart_addr_o <= UART_BASE_ADDR + UART_STATUS_OFFSET;
                    uart_wdata_o <= 32'h0000_0000;
                    uart_sel_o <= 4'b1111;
                    state_q <= TS_POLL_STATUS_WAIT;
                end
                TS_POLL_STATUS_WAIT: begin
                    if (uart_ack_i || uart_err_i) begin
                        uart_req_o <= 1'b0;
                        status_word = uart_rdata_i;
                        if (!uart_err_i && status_word[1]) begin
                            state_q <= TS_READ_RX_REQ;
                        end else if (!uart_err_i && status_word[0] && tx_active_q) begin
                            tx_crc_update_sel = 1'b0;
                            if (tx_idx_q == 8'd0) begin
                                tx_byte_sel = SOF_RESP;
                                tx_crc_update_sel = 1'b1;
                            end else if (tx_idx_q == 8'd1) begin
                                tx_byte_sel = tx_seq_q;
                                tx_crc_update_sel = 1'b1;
                            end else if (tx_idx_q == 8'd2) begin
                                tx_byte_sel = tx_status_q;
                                tx_crc_update_sel = 1'b1;
                            end else if (tx_idx_q == 8'd3) begin
                                tx_byte_sel = tx_payload_len_q;
                                tx_crc_update_sel = 1'b1;
                            end else if (tx_idx_q < (tx_payload_len_q + 8'd4)) begin
                                tx_byte_sel = tx_buf[tx_idx_q - 8'd4];
                                tx_crc_update_sel = 1'b1;
                            end else if (tx_idx_q == (tx_total_len(tx_payload_len_q) - 8'd2)) begin
                                tx_byte_sel = tx_crc_q[15:8];
                            end else begin
                                tx_byte_sel = tx_crc_q[7:0];
                            end
                            tx_byte_q <= tx_byte_sel;
                            tx_crc_update_q <= tx_crc_update_sel;
                            tx_from_fw_q <= 1'b0;
                            state_q <= TS_WRITE_TX_REQ;
                        end else if (!uart_err_i && status_word[0] && fw_tx_valid_i) begin
                            tx_byte_q <= fw_tx_data_i;
                            tx_crc_update_q <= 1'b0;
                            tx_from_fw_q <= 1'b1;
                            state_q <= TS_WRITE_TX_REQ;
                        end else begin
                            state_q <= TS_POLL_STATUS_REQ;
                        end
                    end
                end
                TS_READ_RX_REQ: begin
                    uart_req_o <= 1'b1;
                    uart_we_o <= 1'b0;
                    uart_addr_o <= UART_BASE_ADDR + UART_RXDATA_OFFSET;
                    uart_wdata_o <= 32'h0000_0000;
                    uart_sel_o <= 4'b1111;
                    state_q <= TS_READ_RX_WAIT;
                end
                TS_READ_RX_WAIT: begin
                    if (uart_ack_i || uart_err_i) begin
                        uart_req_o <= 1'b0;
                        state_q <= TS_POLL_STATUS_REQ;
                        if (!uart_err_i) begin
                            rx_byte = uart_rdata_i[7:0];
                            if (rx_state_q == RX_WAIT_SOF) begin
                                if (rx_byte == SOF_REQ) begin
                                    rx_frame_buf[0] <= rx_byte;
                                    rx_frame_count_q <= 6'd1;
                                    rx_crc_calc_q <= crc16_update(16'hFFFF, rx_byte);
                                    rx_state_q <= RX_SEQ;
                                end else if (fw_rx_count_n < FW_RX_FIFO_DEPTH) begin
                                    fw_rx_fifo[fw_rx_wr_ptr_n] <= rx_byte;
                                    fw_rx_wr_ptr_n = fw_rx_wr_ptr_n + 1'b1;
                                    fw_rx_count_n = fw_rx_count_n + 1'b1;
                                end
                            end else begin
                                if (rx_frame_count_q < RX_FRAME_MAX[5:0]) begin
                                    rx_frame_buf[rx_frame_count_q] <= rx_byte;
                                    rx_frame_count_q <= rx_frame_count_q + 6'd1;
                                end
                                case (rx_state_q)
                                    RX_SEQ: begin
                                        rx_seq_q <= rx_byte;
                                        rx_crc_calc_q <= crc16_update(rx_crc_calc_q, rx_byte);
                                        rx_state_q <= RX_CMD;
                                    end
                                    RX_CMD: begin
                                        rx_cmd_q <= rx_byte;
                                        rx_crc_calc_q <= crc16_update(rx_crc_calc_q, rx_byte);
                                        rx_state_q <= RX_LEN;
                                    end
                                    RX_LEN: begin
                                        rx_len_q <= rx_byte;
                                        rx_payload_idx_q <= 6'd0;
                                        rx_crc_calc_q <= crc16_update(rx_crc_calc_q, rx_byte);
                                        if (rx_byte > 8'd32) begin
                                            flush_idx_q <= 6'd0;
                                            flush_count_q <= rx_frame_count_q
                                                          + ((rx_frame_count_q < RX_FRAME_MAX[5:0]) ? 6'd1 : 6'd0);
                                            parser_reset();
                                            state_q <= TS_FLUSH_FRAME;
                                        end else if (rx_byte == 8'd0) begin
                                            rx_state_q <= RX_CRC_H;
                                        end else begin
                                            rx_state_q <= RX_PAYLOAD;
                                        end
                                    end
                                    RX_PAYLOAD: begin
                                        rx_payload[rx_payload_idx_q] <= rx_byte;
                                        rx_crc_calc_q <= crc16_update(rx_crc_calc_q, rx_byte);
                                        if (rx_payload_idx_q + 6'd1 >= rx_len_q[5:0]) begin
                                            rx_state_q <= RX_CRC_H;
                                        end else begin
                                            rx_payload_idx_q <= rx_payload_idx_q + 6'd1;
                                        end
                                    end
                                    RX_CRC_H: begin
                                        rx_crc_recv_q[15:8] <= rx_byte;
                                        rx_state_q <= RX_CRC_L;
                                    end
                                    RX_CRC_L: begin
                                        rx_crc_recv_q[7:0] <= rx_byte;
                                        cmd_seq_o <= rx_seq_q;
                                        cmd_id_o <= rx_cmd_q;
                                        cmd_len_o <= rx_len_q;
                                        for (i = 0; i < 32; i = i + 1) begin
                                            cmd_payload_o[i] <= rx_payload[i];
                                        end
                                        frame_crc_ok_q <= (rx_crc_calc_q == {rx_crc_recv_q[15:8], rx_byte});
                                        frame_ready_q <= 1'b1;
                                        cmd_sent_q <= 1'b0;
                                        if (rx_crc_calc_q == {rx_crc_recv_q[15:8], rx_byte}) begin
                                            state_q <= TS_PROCESS_CMD;
                                        end else begin
                                            flush_idx_q <= 6'd0;
                                            flush_count_q <= rx_frame_count_q
                                                          + ((rx_frame_count_q < RX_FRAME_MAX[5:0]) ? 6'd1 : 6'd0);
                                            state_q <= TS_FLUSH_FRAME;
                                        end
                                        parser_reset();
                                    end
                                    default: begin
                                        parser_reset();
                                    end
                                endcase
                            end
                        end
                    end
                end
                TS_PROCESS_CMD: begin
                    if (!frame_ready_q || !frame_crc_ok_q) begin
                        frame_ready_q <= 1'b0;
                        frame_crc_ok_q <= 1'b0;
                        cmd_sent_q <= 1'b0;
                        state_q <= TS_POLL_STATUS_REQ;
                    end else begin
                        if (!cmd_sent_q && cmd_ready_i) begin
                            cmd_sent_q <= 1'b1;
                        end
                        if (resp_valid_i) begin
                            tx_seq_q <= resp_seq_i;
                            tx_status_q <= resp_status_i;
                            tx_payload_len_q <= resp_len_i;
                            for (i = 0; i < 32; i = i + 1) begin
                                tx_buf[i] <= resp_payload_i[i];
                            end
                            tx_crc_q <= 16'hFFFF;
                            tx_idx_q <= 8'd0;
                            tx_active_q <= 1'b1;
                            frame_ready_q <= 1'b0;
                            frame_crc_ok_q <= 1'b0;
                            cmd_sent_q <= 1'b0;
                            state_q <= TS_POLL_STATUS_REQ;
                        end
                    end
                end
                TS_FLUSH_FRAME: begin
                    if (flush_idx_q >= flush_count_q) begin
                        state_q <= TS_POLL_STATUS_REQ;
                    end else if (fw_rx_count_n < FW_RX_FIFO_DEPTH) begin
                        fw_rx_fifo[fw_rx_wr_ptr_n] <= rx_frame_buf[flush_idx_q];
                        fw_rx_wr_ptr_n = fw_rx_wr_ptr_n + 1'b1;
                        fw_rx_count_n = fw_rx_count_n + 1'b1;
                        flush_idx_q <= flush_idx_q + 6'd1;
                        if (flush_idx_q + 6'd1 >= flush_count_q) begin
                            state_q <= TS_POLL_STATUS_REQ;
                        end
                    end
                end
                TS_WRITE_TX_REQ: begin
                    uart_req_o <= 1'b1;
                    uart_we_o <= 1'b1;
                    uart_addr_o <= UART_BASE_ADDR + UART_TXDATA_OFFSET;
                    uart_wdata_o <= {24'h000000, tx_byte_q};
                    uart_sel_o <= 4'b0001;
                    state_q <= TS_WRITE_TX_WAIT;
                end
                TS_WRITE_TX_WAIT: begin
                    if (uart_ack_i || uart_err_i) begin
                        uart_req_o <= 1'b0;
                        if (!uart_err_i) begin
                            if (!tx_from_fw_q && tx_crc_update_q) begin
                                tx_crc_q <= crc16_update(tx_crc_q, tx_byte_q);
                            end
                            if (!tx_from_fw_q) begin
                                if (tx_idx_q + 8'd1 >= tx_total_len(tx_payload_len_q)) begin
                                    tx_active_q <= 1'b0;
                                    tx_idx_q <= 8'd0;
                                end else begin
                                    tx_idx_q <= tx_idx_q + 8'd1;
                                end
                            end
                        end
                        state_q <= TS_POLL_STATUS_REQ;
                    end
                end
                default: begin
                    state_q <= TS_POLL_STATUS_REQ;
                end
            endcase
            fw_rx_wr_ptr_q <= fw_rx_wr_ptr_n;
            fw_rx_rd_ptr_q <= fw_rx_rd_ptr_n;
            fw_rx_count_q <= fw_rx_count_n;
        end
    end
endmodule : debug_uart_agent_transport
