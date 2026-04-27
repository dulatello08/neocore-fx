//
// debug_uart_agent.sv
// NeoCoreFX - External UART hardware debug agent (ncdb front-end)
//

module debug_uart_agent #(
    parameter bit          BOOT_DEFAULT_ACTIVE = 1'b1,
    parameter int unsigned CLAIM_WINDOW_CYCLES = 400_000_000,
    parameter int unsigned MEM_TIMEOUT_CYCLES = 4096
) (
    input  logic        clk,
    input  logic        rst,

    // Physical UART MMIO backend access (ncdb always owns this path).
    output logic        uart_req_o,
    output logic        uart_we_o,
    output logic [31:0] uart_addr_o,
    output logic [31:0] uart_wdata_o,
    output logic [3:0]  uart_sel_o,
    input  logic        uart_ack_i,
    input  logic [31:0] uart_rdata_i,
    input  logic        uart_err_i,

    // Core debug surface (direct, hardware-only control path).
    input  logic        core_halted_i,
    input  logic [2:0]  core_halt_reason_i,
    input  logic [31:0] core_pc_i,
    input  logic        core_last_fault_i,
    input  logic [31:0] core_last_fault_pc_i,
    input  logic [31:0] core_last_fault_addr_i,
    input  logic [31:0] core_last_illegal_inst_i,

    output logic        halt_req_o,
    output logic        resume_req_o,
    output logic        step_req_o,
    output logic        pc_set_req_o,
    output logic [31:0] pc_set_data_o,

    output logic [3:0]  gpr_addr_o,
    input  logic [31:0] gpr_rdata_i,
    output logic        gpr_we_o,
    output logic [31:0] gpr_wdata_o,

    input  logic [31:0] cycle_count_i,
    input  logic [31:0] retire_count_i,
    input  logic [31:0] branch_redirect_count_i,
    input  logic [31:0] load_stall_count_i,
    input  logic [31:0] mem_stall_count_i,

    output logic        dbg_mem_req_o,
    output logic        dbg_mem_we_o,
    output logic [1:0]  dbg_mem_size_o,
    output logic [31:0] dbg_mem_addr_o,
    output logic [31:0] dbg_mem_wdata_o,
    input  logic        dbg_mem_done_i,
    input  logic [31:0] dbg_mem_rdata_i,
    input  logic        dbg_mem_err_i,

    // Virtual firmware console stream bridge.
    output logic        fw_rx_valid_o,
    output logic [7:0]  fw_rx_data_o,
    input  logic        fw_rx_ready_i,

    input  logic        fw_tx_valid_i,
    input  logic [7:0]  fw_tx_data_i,
    output logic        fw_tx_ready_o,

    output logic        uart_debug_owned_o,
    output logic        debug_active_o
);
    timeunit 1ns;
    timeprecision 1ps;

    import mem_pkg::*;

    localparam logic [7:0] SOF_REQ  = 8'hA5;
    localparam logic [7:0] SOF_RESP = 8'h5A;

    localparam logic [7:0] CMD_HELLO         = 8'h00;
    localparam logic [7:0] CMD_CLAIM         = 8'h01;
    localparam logic [7:0] CMD_RELEASE       = 8'h02;
    localparam logic [7:0] CMD_HALT          = 8'h10;
    localparam logic [7:0] CMD_RESUME        = 8'h11;
    localparam logic [7:0] CMD_STEP          = 8'h12;
    localparam logic [7:0] CMD_SET_PC        = 8'h13;
    localparam logic [7:0] CMD_READ_STATUS   = 8'h20;
    localparam logic [7:0] CMD_READ_GPR      = 8'h21;
    localparam logic [7:0] CMD_WRITE_GPR     = 8'h22;
    localparam logic [7:0] CMD_READ_MEM      = 8'h23;
    localparam logic [7:0] CMD_WRITE_MEM     = 8'h24;
    localparam logic [7:0] CMD_READ_COUNTERS = 8'h25;
    localparam logic [7:0] CMD_READ_MEM_BURST = 8'h26;
    localparam logic [7:0] CMD_SET_MEM_BURST  = 8'h27;

    localparam logic [7:0] ST_OK         = 8'h00;
    localparam logic [7:0] ST_BAD_CMD    = 8'h02;
    localparam logic [7:0] ST_BUS_ERR    = 8'h03;
    localparam logic [7:0] ST_NOT_HALTED = 8'h05;
    localparam logic [7:0] ST_TIMEOUT    = 8'h06;

    localparam logic [1:0] SIZE_BYTE = 2'b00;
    localparam logic [1:0] SIZE_HALF = 2'b01;
    localparam logic [1:0] SIZE_WORD = 2'b10;

    localparam int unsigned FW_RX_FIFO_DEPTH = 64;
    localparam int unsigned FW_RX_PTR_W = $clog2(FW_RX_FIFO_DEPTH);
    localparam int unsigned FW_RX_COUNT_W = $clog2(FW_RX_FIFO_DEPTH + 1);

    localparam int unsigned RX_FRAME_MAX = 40;

    typedef enum logic [3:0] {
        S_POLL_STATUS_REQ  = 4'd0,
        S_POLL_STATUS_WAIT = 4'd1,
        S_READ_RX_REQ      = 4'd2,
        S_READ_RX_WAIT     = 4'd3,
        S_WRITE_TX_REQ     = 4'd4,
        S_WRITE_TX_WAIT    = 4'd5,
        S_PROCESS_CMD      = 4'd6,
        S_MEM_WAIT         = 4'd7,
        S_GPR_READ_DELAY   = 4'd8,
        S_FLUSH_FRAME      = 4'd9
    } state_t;

    typedef enum logic [2:0] {
        RX_WAIT_SOF = 3'd0,
        RX_SEQ      = 3'd1,
        RX_CMD      = 3'd2,
        RX_LEN      = 3'd3,
        RX_PAYLOAD  = 3'd4,
        RX_CRC_H    = 3'd5,
        RX_CRC_L    = 3'd6
    } rx_state_t;

    state_t state_q;

    logic uart_req_q;
    logic uart_we_q;
    logic [31:0] uart_addr_q;
    logic [31:0] uart_wdata_q;
    logic [3:0]  uart_sel_q;

    logic [7:0] tx_buf [0:31];
    logic [7:0] tx_payload_len_q;
    logic [7:0] tx_idx_q;
    logic       tx_active_q;
    logic [7:0] tx_seq_q;
    logic [7:0] tx_status_q;
    logic [15:0] tx_crc_q;
    logic [7:0] tx_byte_q;
    logic       tx_crc_update_q;
    logic       tx_from_fw_q;

    rx_state_t  rx_state_q;
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

    logic [7:0] cmd_seq_q;
    logic [7:0] cmd_id_q;
    logic [7:0] cmd_len_q;
    logic [7:0] cmd_payload [0:31];

    logic [31:0] mem_timeout_ctr_q;
    logic mem_cmd_is_read_q;
    logic mem_burst_active_q;
    logic mem_burst_is_set_q;
    logic [7:0] mem_burst_total_q;
    logic [7:0] mem_burst_remaining_q;
    logic [7:0] mem_burst_index_q;
    logic [31:0] mem_burst_addr_q;
    logic [31:0] mem_burst_value_q;

    logic [3:0] gpr_addr_q;
    logic [31:0] gpr_wdata_q;
    logic [31:0] pc_set_data_q;

    logic dbg_mem_busy_q;
    logic dbg_mem_we_q;
    logic [1:0] dbg_mem_size_q;
    logic [31:0] dbg_mem_addr_q;
    logic [31:0] dbg_mem_wdata_q;

    logic [7:0] fw_rx_fifo [0:FW_RX_FIFO_DEPTH-1];
    logic [FW_RX_PTR_W-1:0] fw_rx_wr_ptr_q;
    logic [FW_RX_PTR_W-1:0] fw_rx_rd_ptr_q;
    logic [FW_RX_COUNT_W-1:0] fw_rx_count_q;

    integer i;

    function automatic logic [15:0] crc16_update(input logic [15:0] crc_in, input logic [7:0] data);
        logic [15:0] crc;
        logic [7:0] d;
        int bit_idx;
        begin
            crc = crc_in;
            d = data;
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                if ((crc[15] ^ d[7]) == 1'b1) begin
                    crc = (crc << 1) ^ 16'h1021;
                end else begin
                    crc = (crc << 1);
                end
                d = {d[6:0], 1'b0};
            end
            return crc;
        end
    endfunction

    function automatic logic [31:0] payload_word_be(input logic [7:0] p0, input logic [7:0] p1,
                                                    input logic [7:0] p2, input logic [7:0] p3);
        return {p0, p1, p2, p3};
    endfunction

    function automatic logic [7:0] tx_total_len(input logic [7:0] payload_len);
        return payload_len + 8'd6;
    endfunction

    function automatic logic [31:0] mem_stride_bytes(input logic [1:0] size);
        begin
            case (size)
                SIZE_BYTE: return 32'd1;
                SIZE_HALF: return 32'd2;
                default: return 32'd4;
            endcase
        end
    endfunction

    task automatic queue_response_no_payload(
        input logic [7:0] seq,
        input logic [7:0] status
    );
        begin
            tx_seq_q <= seq;
            tx_status_q <= status;
            tx_payload_len_q <= 8'd0;
            tx_crc_q <= 16'hFFFF;
            tx_idx_q <= 8'd0;
            tx_active_q <= 1'b1;
        end
    endtask

    task automatic queue_response_word(
        input logic [7:0] seq,
        input logic [7:0] status,
        input logic [31:0] word
    );
        begin
            tx_seq_q <= seq;
            tx_status_q <= status;
            tx_payload_len_q <= 8'd4;
            tx_crc_q <= 16'hFFFF;
            tx_buf[0] <= word[31:24];
            tx_buf[1] <= word[23:16];
            tx_buf[2] <= word[15:8];
            tx_buf[3] <= word[7:0];
            tx_idx_q <= 8'd0;
            tx_active_q <= 1'b1;
        end
    endtask

    task automatic queue_response_buffer(
        input logic [7:0] seq,
        input logic [7:0] status,
        input logic [7:0] payload_len
    );
        begin
            tx_seq_q <= seq;
            tx_status_q <= status;
            tx_payload_len_q <= payload_len;
            tx_crc_q <= 16'hFFFF;
            tx_idx_q <= 8'd0;
            tx_active_q <= 1'b1;
        end
    endtask

    task automatic queue_response_words5(
        input logic [7:0] seq,
        input logic [7:0] status,
        input logic [31:0] w0,
        input logic [31:0] w1,
        input logic [31:0] w2,
        input logic [31:0] w3,
        input logic [31:0] w4
    );
        begin
            tx_seq_q <= seq;
            tx_status_q <= status;
            tx_payload_len_q <= 8'd20;
            tx_crc_q <= 16'hFFFF;

            tx_buf[0]  <= w0[31:24]; tx_buf[1]  <= w0[23:16]; tx_buf[2]  <= w0[15:8]; tx_buf[3]  <= w0[7:0];
            tx_buf[4]  <= w1[31:24]; tx_buf[5]  <= w1[23:16]; tx_buf[6]  <= w1[15:8]; tx_buf[7]  <= w1[7:0];
            tx_buf[8]  <= w2[31:24]; tx_buf[9]  <= w2[23:16]; tx_buf[10] <= w2[15:8]; tx_buf[11] <= w2[7:0];
            tx_buf[12] <= w3[31:24]; tx_buf[13] <= w3[23:16]; tx_buf[14] <= w3[15:8]; tx_buf[15] <= w3[7:0];
            tx_buf[16] <= w4[31:24]; tx_buf[17] <= w4[23:16]; tx_buf[18] <= w4[15:8]; tx_buf[19] <= w4[7:0];

            tx_idx_q <= 8'd0;
            tx_active_q <= 1'b1;
        end
    endtask

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

    assign uart_req_o = uart_req_q;
    assign uart_we_o = uart_we_q;
    assign uart_addr_o = uart_addr_q;
    assign uart_wdata_o = uart_wdata_q;
    assign uart_sel_o = uart_sel_q;

    assign uart_debug_owned_o = 1'b1;
    assign debug_active_o = frame_ready_q || (state_q == S_PROCESS_CMD) || (state_q == S_MEM_WAIT) || (state_q == S_GPR_READ_DELAY);

    assign gpr_addr_o = gpr_addr_q;
    assign gpr_wdata_o = gpr_wdata_q;
    assign pc_set_data_o = pc_set_data_q;

    assign dbg_mem_req_o = dbg_mem_busy_q;
    assign dbg_mem_we_o = dbg_mem_we_q;
    assign dbg_mem_size_o = dbg_mem_size_q;
    assign dbg_mem_addr_o = dbg_mem_addr_q;
    assign dbg_mem_wdata_o = dbg_mem_wdata_q;

    assign fw_rx_valid_o = (fw_rx_count_q != 0);
    assign fw_rx_data_o = (fw_rx_count_q != 0) ? fw_rx_fifo[fw_rx_rd_ptr_q] : 8'h00;

    // Consume one firmware TX byte only when status read confirms TX-ready and no host RX pending.
    assign fw_tx_ready_o = (state_q == S_POLL_STATUS_WAIT)
                        && uart_ack_i
                        && !uart_err_i
                        && uart_rdata_i[0]
                        && !uart_rdata_i[1]
                        && !tx_active_q;

    always @(posedge clk) begin
        logic [7:0] rx_byte;
        logic [31:0] status_word;
        logic [31:0] mem_addr_word;
        logic [31:0] mem_data_word;
        logic [1:0]  mem_size_field;
        logic [31:0] status_payload_word;

        logic [7:0] tx_byte_sel;
        logic tx_crc_update_sel;

        logic [FW_RX_PTR_W-1:0] fw_rx_wr_ptr_n;
        logic [FW_RX_PTR_W-1:0] fw_rx_rd_ptr_n;
        logic [FW_RX_COUNT_W-1:0] fw_rx_count_n;
        halt_req_o <= 1'b0;
        resume_req_o <= 1'b0;
        step_req_o <= 1'b0;
        pc_set_req_o <= 1'b0;
        gpr_we_o <= 1'b0;

        if (rst) begin
            uart_req_q <= 1'b0;
            uart_we_q <= 1'b0;
            uart_addr_q <= 32'h0000_0000;
            uart_wdata_q <= 32'h0000_0000;
            uart_sel_q <= 4'b1111;

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

            cmd_seq_q <= 8'h00;
            cmd_id_q <= 8'h00;
            cmd_len_q <= 8'h00;

            mem_timeout_ctr_q <= 32'h0000_0000;
            mem_cmd_is_read_q <= 1'b0;
            mem_burst_active_q <= 1'b0;
            mem_burst_is_set_q <= 1'b0;
            mem_burst_total_q <= 8'd0;
            mem_burst_remaining_q <= 8'd0;
            mem_burst_index_q <= 8'd0;
            mem_burst_addr_q <= 32'h0000_0000;
            mem_burst_value_q <= 32'h0000_0000;

            gpr_addr_q <= 4'h0;
            gpr_wdata_q <= 32'h0000_0000;
            pc_set_data_q <= 32'h0000_0000;

            dbg_mem_busy_q <= 1'b0;
            dbg_mem_we_q <= 1'b0;
            dbg_mem_size_q <= SIZE_WORD;
            dbg_mem_addr_q <= 32'h0000_0000;
            dbg_mem_wdata_q <= 32'h0000_0000;

            fw_rx_wr_ptr_q <= '0;
            fw_rx_rd_ptr_q <= '0;
            fw_rx_count_q <= '0;
            flush_idx_q <= 6'd0;
            flush_count_q <= 6'd0;

            state_q <= S_POLL_STATUS_REQ;
        end else begin
            // Firmware RX dequeue side (towards virtual UART endpoint).
            fw_rx_wr_ptr_n = fw_rx_wr_ptr_q;
            fw_rx_rd_ptr_n = fw_rx_rd_ptr_q;
            fw_rx_count_n = fw_rx_count_q;
            if ((fw_rx_count_n != 0) && fw_rx_ready_i) begin
                fw_rx_rd_ptr_n = fw_rx_rd_ptr_n + 1'b1;
                fw_rx_count_n = fw_rx_count_n - 1'b1;
            end

            if (frame_ready_q) begin
                frame_ready_q <= 1'b0;
            end

            case (state_q)
                S_POLL_STATUS_REQ: begin
                    uart_req_q <= 1'b1;
                    uart_we_q <= 1'b0;
                    uart_addr_q <= UART_BASE_ADDR + UART_STATUS_OFFSET;
                    uart_wdata_q <= 32'h0000_0000;
                    uart_sel_q <= 4'b1111;
                    state_q <= S_POLL_STATUS_WAIT;
                end

                S_POLL_STATUS_WAIT: begin
                    if (uart_ack_i || uart_err_i) begin
                        uart_req_q <= 1'b0;
                        status_word = uart_rdata_i;
                        if (!uart_err_i && status_word[1]) begin
                            state_q <= S_READ_RX_REQ;
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
                            state_q <= S_WRITE_TX_REQ;
                        end else if (!uart_err_i && status_word[0] && fw_tx_valid_i) begin
                            tx_byte_q <= fw_tx_data_i;
                            tx_crc_update_q <= 1'b0;
                            tx_from_fw_q <= 1'b1;
                            state_q <= S_WRITE_TX_REQ;
                        end else begin
                            state_q <= S_POLL_STATUS_REQ;
                        end
                    end
                end

                S_READ_RX_REQ: begin
                    uart_req_q <= 1'b1;
                    uart_we_q <= 1'b0;
                    uart_addr_q <= UART_BASE_ADDR + UART_RXDATA_OFFSET;
                    uart_wdata_q <= 32'h0000_0000;
                    uart_sel_q <= 4'b1111;
                    state_q <= S_READ_RX_WAIT;
                end

                S_READ_RX_WAIT: begin
                    if (uart_ack_i || uart_err_i) begin
                        uart_req_q <= 1'b0;
                        state_q <= S_POLL_STATUS_REQ;
                        if (!uart_err_i) begin
                            rx_byte = uart_rdata_i[7:0];

                            if (rx_state_q == RX_WAIT_SOF) begin
                                if (rx_byte == SOF_REQ) begin
                                    rx_frame_buf[0] <= rx_byte;
                                    rx_frame_count_q <= 6'd1;
                                    rx_crc_calc_q <= crc16_update(16'hFFFF, rx_byte);
                                    rx_state_q <= RX_SEQ;
                                end else begin
                                    if (fw_rx_count_n < FW_RX_FIFO_DEPTH) begin
                                        fw_rx_fifo[fw_rx_wr_ptr_n] <= rx_byte;
                                        fw_rx_wr_ptr_n = fw_rx_wr_ptr_n + 1'b1;
                                        fw_rx_count_n = fw_rx_count_n + 1'b1;
                                    end
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
                                            flush_count_q <= rx_frame_count_q + ((rx_frame_count_q < RX_FRAME_MAX[5:0]) ? 6'd1 : 6'd0);
                                            parser_reset();
                                            state_q <= S_FLUSH_FRAME;
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
                                        cmd_seq_q <= rx_seq_q;
                                        cmd_id_q <= rx_cmd_q;
                                        cmd_len_q <= rx_len_q;
                                        for (i = 0; i < 32; i = i + 1) begin
                                            cmd_payload[i] <= rx_payload[i];
                                        end
                                        frame_crc_ok_q <= (rx_crc_calc_q == {rx_crc_recv_q[15:8], rx_byte});
                                        frame_ready_q <= 1'b1;

                                        if (rx_crc_calc_q == {rx_crc_recv_q[15:8], rx_byte}) begin
                                            state_q <= S_PROCESS_CMD;
                                        end else begin
                                            flush_idx_q <= 6'd0;
                                            flush_count_q <= rx_frame_count_q + ((rx_frame_count_q < RX_FRAME_MAX[5:0]) ? 6'd1 : 6'd0);
                                            state_q <= S_FLUSH_FRAME;
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

                S_PROCESS_CMD: begin
                    if (!frame_ready_q || !frame_crc_ok_q) begin
                        state_q <= S_POLL_STATUS_REQ;
                    end else begin
                        case (cmd_id_q)
                            CMD_HELLO: begin
                                queue_response_word(cmd_seq_q, ST_OK, 32'h4E43_4442); // NCDB
                                state_q <= S_POLL_STATUS_REQ;
                            end

                            // Keep these as compatibility no-ops.
                            CMD_CLAIM: begin
                                queue_response_no_payload(cmd_seq_q, ST_OK);
                                state_q <= S_POLL_STATUS_REQ;
                            end

                            CMD_RELEASE: begin
                                queue_response_no_payload(cmd_seq_q, ST_OK);
                                state_q <= S_POLL_STATUS_REQ;
                            end

                            CMD_HALT: begin
                                halt_req_o <= 1'b1;
                                queue_response_no_payload(cmd_seq_q, ST_OK);
                                state_q <= S_POLL_STATUS_REQ;
                            end

                            CMD_RESUME: begin
                                resume_req_o <= 1'b1;
                                queue_response_no_payload(cmd_seq_q, ST_OK);
                                state_q <= S_POLL_STATUS_REQ;
                            end

                            CMD_STEP: begin
                                step_req_o <= 1'b1;
                                queue_response_no_payload(cmd_seq_q, ST_OK);
                                state_q <= S_POLL_STATUS_REQ;
                            end

                            CMD_SET_PC: begin
                                if (cmd_len_q != 8'd4) begin
                                    queue_response_no_payload(cmd_seq_q, ST_BAD_CMD);
                                end else if (!core_halted_i) begin
                                    queue_response_no_payload(cmd_seq_q, ST_NOT_HALTED);
                                end else begin
                                    pc_set_data_q <= payload_word_be(cmd_payload[0], cmd_payload[1], cmd_payload[2], cmd_payload[3]);
                                    pc_set_req_o <= 1'b1;
                                    queue_response_no_payload(cmd_seq_q, ST_OK);
                                end
                                state_q <= S_POLL_STATUS_REQ;
                            end

                            CMD_READ_STATUS: begin
                                status_payload_word = {
                                    24'h000000,
                                    core_last_fault_i,
                                    core_halt_reason_i,
                                    3'b000,
                                    core_halted_i
                                };
                                queue_response_words5(
                                    cmd_seq_q,
                                    ST_OK,
                                    status_payload_word,
                                    core_pc_i,
                                    core_last_fault_pc_i,
                                    core_last_fault_addr_i,
                                    core_last_illegal_inst_i
                                );
                                state_q <= S_POLL_STATUS_REQ;
                            end

                            CMD_READ_GPR: begin
                                if (cmd_len_q != 8'd1) begin
                                    queue_response_no_payload(cmd_seq_q, ST_BAD_CMD);
                                    state_q <= S_POLL_STATUS_REQ;
                                end else begin
                                    gpr_addr_q <= cmd_payload[0][3:0];
                                    state_q <= S_GPR_READ_DELAY;
                                end
                            end

                            CMD_WRITE_GPR: begin
                                if (cmd_len_q != 8'd5) begin
                                    queue_response_no_payload(cmd_seq_q, ST_BAD_CMD);
                                end else if (!core_halted_i) begin
                                    queue_response_no_payload(cmd_seq_q, ST_NOT_HALTED);
                                end else begin
                                    gpr_addr_q <= cmd_payload[0][3:0];
                                    gpr_wdata_q <= payload_word_be(cmd_payload[1], cmd_payload[2], cmd_payload[3], cmd_payload[4]);
                                    gpr_we_o <= 1'b1;
                                    queue_response_no_payload(cmd_seq_q, ST_OK);
                                end
                                state_q <= S_POLL_STATUS_REQ;
                            end

                            CMD_READ_MEM: begin
                                if (cmd_len_q != 8'd5) begin
                                    queue_response_no_payload(cmd_seq_q, ST_BAD_CMD);
                                    state_q <= S_POLL_STATUS_REQ;
                                end else if (!core_halted_i) begin
                                    queue_response_no_payload(cmd_seq_q, ST_NOT_HALTED);
                                    state_q <= S_POLL_STATUS_REQ;
                                end else begin
                                    mem_addr_word = payload_word_be(cmd_payload[0], cmd_payload[1], cmd_payload[2], cmd_payload[3]);
                                    mem_size_field = cmd_payload[4][1:0];
                                    dbg_mem_addr_q <= mem_addr_word;
                                    dbg_mem_wdata_q <= 32'h0000_0000;
                                    dbg_mem_size_q <= (mem_size_field == 2'b00) ? SIZE_BYTE
                                                     : (mem_size_field == 2'b01) ? SIZE_HALF
                                                     : SIZE_WORD;
                                    dbg_mem_we_q <= 1'b0;
                                    dbg_mem_busy_q <= 1'b1;
                                    mem_cmd_is_read_q <= 1'b1;
                                    mem_timeout_ctr_q <= 32'h0000_0000;
                                    state_q <= S_MEM_WAIT;
                                end
                            end

                            CMD_WRITE_MEM: begin
                                if (cmd_len_q != 8'd9) begin
                                    queue_response_no_payload(cmd_seq_q, ST_BAD_CMD);
                                    state_q <= S_POLL_STATUS_REQ;
                                end else if (!core_halted_i) begin
                                    queue_response_no_payload(cmd_seq_q, ST_NOT_HALTED);
                                    state_q <= S_POLL_STATUS_REQ;
                                end else begin
                                    mem_addr_word = payload_word_be(cmd_payload[0], cmd_payload[1], cmd_payload[2], cmd_payload[3]);
                                    mem_size_field = cmd_payload[4][1:0];
                                    mem_data_word = payload_word_be(cmd_payload[5], cmd_payload[6], cmd_payload[7], cmd_payload[8]);
                                    dbg_mem_addr_q <= mem_addr_word;
                                    dbg_mem_wdata_q <= mem_data_word;
                                    dbg_mem_size_q <= (mem_size_field == 2'b00) ? SIZE_BYTE
                                                     : (mem_size_field == 2'b01) ? SIZE_HALF
                                                     : SIZE_WORD;
                                    dbg_mem_we_q <= 1'b1;
                                    dbg_mem_busy_q <= 1'b1;
                                    mem_cmd_is_read_q <= 1'b0;
                                    mem_timeout_ctr_q <= 32'h0000_0000;
                                    state_q <= S_MEM_WAIT;
                                end
                            end

                            CMD_READ_COUNTERS: begin
                                queue_response_words5(
                                    cmd_seq_q,
                                    ST_OK,
                                    cycle_count_i,
                                    retire_count_i,
                                    branch_redirect_count_i,
                                    load_stall_count_i,
                                    mem_stall_count_i
                                );
                                state_q <= S_POLL_STATUS_REQ;
                            end

                            CMD_READ_MEM_BURST: begin
                                if (cmd_len_q != 8'd6) begin
                                    queue_response_no_payload(cmd_seq_q, ST_BAD_CMD);
                                    state_q <= S_POLL_STATUS_REQ;
                                end else if (!core_halted_i) begin
                                    queue_response_no_payload(cmd_seq_q, ST_NOT_HALTED);
                                    state_q <= S_POLL_STATUS_REQ;
                                end else if ((cmd_payload[5] == 8'd0) || (cmd_payload[5] > 8'd8)) begin
                                    queue_response_no_payload(cmd_seq_q, ST_BAD_CMD);
                                    state_q <= S_POLL_STATUS_REQ;
                                end else begin
                                    mem_addr_word = payload_word_be(cmd_payload[0], cmd_payload[1], cmd_payload[2], cmd_payload[3]);
                                    mem_size_field = cmd_payload[4][1:0];
                                    dbg_mem_addr_q <= mem_addr_word;
                                    dbg_mem_wdata_q <= 32'h0000_0000;
                                    dbg_mem_size_q <= (mem_size_field == 2'b00) ? SIZE_BYTE
                                                     : (mem_size_field == 2'b01) ? SIZE_HALF
                                                     : SIZE_WORD;
                                    dbg_mem_we_q <= 1'b0;
                                    dbg_mem_busy_q <= 1'b1;
                                    mem_cmd_is_read_q <= 1'b1;
                                    mem_timeout_ctr_q <= 32'h0000_0000;
                                    mem_burst_active_q <= 1'b1;
                                    mem_burst_is_set_q <= 1'b0;
                                    mem_burst_total_q <= cmd_payload[5];
                                    mem_burst_remaining_q <= cmd_payload[5];
                                    mem_burst_index_q <= 8'd0;
                                    mem_burst_addr_q <= mem_addr_word;
                                    mem_burst_value_q <= 32'h0000_0000;
                                    state_q <= S_MEM_WAIT;
                                end
                            end

                            CMD_SET_MEM_BURST: begin
                                if (cmd_len_q != 8'd10) begin
                                    queue_response_no_payload(cmd_seq_q, ST_BAD_CMD);
                                    state_q <= S_POLL_STATUS_REQ;
                                end else if (!core_halted_i) begin
                                    queue_response_no_payload(cmd_seq_q, ST_NOT_HALTED);
                                    state_q <= S_POLL_STATUS_REQ;
                                end else if (cmd_payload[5] == 8'd0) begin
                                    queue_response_no_payload(cmd_seq_q, ST_BAD_CMD);
                                    state_q <= S_POLL_STATUS_REQ;
                                end else begin
                                    mem_addr_word = payload_word_be(cmd_payload[0], cmd_payload[1], cmd_payload[2], cmd_payload[3]);
                                    mem_size_field = cmd_payload[4][1:0];
                                    mem_data_word = payload_word_be(cmd_payload[6], cmd_payload[7], cmd_payload[8], cmd_payload[9]);
                                    dbg_mem_addr_q <= mem_addr_word;
                                    dbg_mem_wdata_q <= mem_data_word;
                                    dbg_mem_size_q <= (mem_size_field == 2'b00) ? SIZE_BYTE
                                                     : (mem_size_field == 2'b01) ? SIZE_HALF
                                                     : SIZE_WORD;
                                    dbg_mem_we_q <= 1'b1;
                                    dbg_mem_busy_q <= 1'b1;
                                    mem_cmd_is_read_q <= 1'b0;
                                    mem_timeout_ctr_q <= 32'h0000_0000;
                                    mem_burst_active_q <= 1'b1;
                                    mem_burst_is_set_q <= 1'b1;
                                    mem_burst_total_q <= cmd_payload[5];
                                    mem_burst_remaining_q <= cmd_payload[5];
                                    mem_burst_index_q <= 8'd0;
                                    mem_burst_addr_q <= mem_addr_word;
                                    mem_burst_value_q <= mem_data_word;
                                    state_q <= S_MEM_WAIT;
                                end
                            end

                            default: begin
                                queue_response_no_payload(cmd_seq_q, ST_BAD_CMD);
                                state_q <= S_POLL_STATUS_REQ;
                            end
                        endcase
                    end
                end

                S_GPR_READ_DELAY: begin
                    queue_response_word(cmd_seq_q, ST_OK, gpr_rdata_i);
                    state_q <= S_POLL_STATUS_REQ;
                end

                S_FLUSH_FRAME: begin
                    if (flush_idx_q >= flush_count_q) begin
                        state_q <= S_POLL_STATUS_REQ;
                    end else if (fw_rx_count_n < FW_RX_FIFO_DEPTH) begin
                        fw_rx_fifo[fw_rx_wr_ptr_n] <= rx_frame_buf[flush_idx_q];
                        fw_rx_wr_ptr_n = fw_rx_wr_ptr_n + 1'b1;
                        fw_rx_count_n = fw_rx_count_n + 1'b1;
                        flush_idx_q <= flush_idx_q + 6'd1;
                        if (flush_idx_q + 6'd1 >= flush_count_q) begin
                            state_q <= S_POLL_STATUS_REQ;
                        end
                    end
                end

                S_MEM_WAIT: begin
                    if (dbg_mem_done_i) begin
                        if (mem_burst_active_q) begin
                            if (dbg_mem_err_i) begin
                                dbg_mem_busy_q <= 1'b0;
                                mem_burst_active_q <= 1'b0;
                                queue_response_no_payload(cmd_seq_q, ST_BUS_ERR);
                                state_q <= S_POLL_STATUS_REQ;
                            end else begin
                                if (!mem_burst_is_set_q) begin
                                    tx_buf[(mem_burst_index_q * 8'd4) + 8'd0] <= dbg_mem_rdata_i[31:24];
                                    tx_buf[(mem_burst_index_q * 8'd4) + 8'd1] <= dbg_mem_rdata_i[23:16];
                                    tx_buf[(mem_burst_index_q * 8'd4) + 8'd2] <= dbg_mem_rdata_i[15:8];
                                    tx_buf[(mem_burst_index_q * 8'd4) + 8'd3] <= dbg_mem_rdata_i[7:0];
                                end

                                if (mem_burst_remaining_q <= 8'd1) begin
                                    dbg_mem_busy_q <= 1'b0;
                                    mem_burst_active_q <= 1'b0;
                                    if (mem_burst_is_set_q) begin
                                        queue_response_no_payload(cmd_seq_q, ST_OK);
                                    end else begin
                                        queue_response_buffer(cmd_seq_q, ST_OK, mem_burst_total_q * 8'd4);
                                    end
                                    state_q <= S_POLL_STATUS_REQ;
                                end else begin
                                    mem_burst_addr_q <= mem_burst_addr_q + mem_stride_bytes(dbg_mem_size_q);
                                    mem_burst_index_q <= mem_burst_index_q + 8'd1;
                                    mem_burst_remaining_q <= mem_burst_remaining_q - 8'd1;
                                    dbg_mem_addr_q <= mem_burst_addr_q + mem_stride_bytes(dbg_mem_size_q);
                                    dbg_mem_wdata_q <= mem_burst_value_q;
                                    dbg_mem_we_q <= mem_burst_is_set_q;
                                    dbg_mem_busy_q <= 1'b1;
                                    mem_timeout_ctr_q <= 32'h0000_0000;
                                    state_q <= S_MEM_WAIT;
                                end
                            end
                        end else if (dbg_mem_err_i) begin
                            dbg_mem_busy_q <= 1'b0;
                            queue_response_no_payload(cmd_seq_q, ST_BUS_ERR);
                            state_q <= S_POLL_STATUS_REQ;
                        end else if (mem_cmd_is_read_q) begin
                            dbg_mem_busy_q <= 1'b0;
                            queue_response_word(cmd_seq_q, ST_OK, dbg_mem_rdata_i);
                            state_q <= S_POLL_STATUS_REQ;
                        end else begin
                            dbg_mem_busy_q <= 1'b0;
                            queue_response_no_payload(cmd_seq_q, ST_OK);
                            state_q <= S_POLL_STATUS_REQ;
                        end
                    end else if (mem_timeout_ctr_q >= MEM_TIMEOUT_CYCLES) begin
                        dbg_mem_busy_q <= 1'b0;
                        mem_burst_active_q <= 1'b0;
                        queue_response_no_payload(cmd_seq_q, ST_TIMEOUT);
                        state_q <= S_POLL_STATUS_REQ;
                    end else begin
                        mem_timeout_ctr_q <= mem_timeout_ctr_q + 32'd1;
                    end
                end

                S_WRITE_TX_REQ: begin
                    uart_req_q <= 1'b1;
                    uart_we_q <= 1'b1;
                    uart_addr_q <= UART_BASE_ADDR + UART_TXDATA_OFFSET;
                    uart_wdata_q <= {24'h000000, tx_byte_q};
                    uart_sel_q <= 4'b0001;
                    state_q <= S_WRITE_TX_WAIT;
                end

                S_WRITE_TX_WAIT: begin
                    if (uart_ack_i || uart_err_i) begin
                        uart_req_q <= 1'b0;
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
                        state_q <= S_POLL_STATUS_REQ;
                    end
                end

                default: begin
                    state_q <= S_POLL_STATUS_REQ;
                end
            endcase

            fw_rx_wr_ptr_q <= fw_rx_wr_ptr_n;
            fw_rx_rd_ptr_q <= fw_rx_rd_ptr_n;
            fw_rx_count_q <= fw_rx_count_n;
        end
    end

    logic unused_claim;
    assign unused_claim = BOOT_DEFAULT_ACTIVE ^ CLAIM_WINDOW_CYCLES[0] ^ core_last_fault_addr_i[0] ^ core_last_illegal_inst_i[0];
endmodule : debug_uart_agent
