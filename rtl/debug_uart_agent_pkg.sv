package debug_uart_agent_pkg;
    timeunit 1ns;
    timeprecision 1ps;
    localparam logic [7:0] SOF_REQ  = 8'hA5;
    localparam logic [7:0] SOF_RESP = 8'h5A;

    localparam logic [7:0] CMD_HELLO          = 8'h00;
    localparam logic [7:0] CMD_CLAIM          = 8'h01;
    localparam logic [7:0] CMD_RELEASE        = 8'h02;
    localparam logic [7:0] CMD_HALT           = 8'h10;
    localparam logic [7:0] CMD_RESUME         = 8'h11;
    localparam logic [7:0] CMD_STEP           = 8'h12;
    localparam logic [7:0] CMD_SET_PC         = 8'h13;
    localparam logic [7:0] CMD_READ_STATUS    = 8'h20;
    localparam logic [7:0] CMD_READ_GPR       = 8'h21;
    localparam logic [7:0] CMD_WRITE_GPR      = 8'h22;
    localparam logic [7:0] CMD_READ_MEM       = 8'h23;
    localparam logic [7:0] CMD_WRITE_MEM      = 8'h24;
    localparam logic [7:0] CMD_READ_COUNTERS  = 8'h25;
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

    typedef enum logic [2:0] {
        RX_WAIT_SOF = 3'd0,
        RX_SEQ      = 3'd1,
        RX_CMD      = 3'd2,
        RX_LEN      = 3'd3,
        RX_PAYLOAD  = 3'd4,
        RX_CRC_H    = 3'd5,
        RX_CRC_L    = 3'd6
    } rx_state_t;

    typedef enum logic [2:0] {
        TS_POLL_STATUS_REQ  = 3'd0,
        TS_POLL_STATUS_WAIT = 3'd1,
        TS_READ_RX_REQ      = 3'd2,
        TS_READ_RX_WAIT     = 3'd3,
        TS_WRITE_TX_REQ     = 3'd4,
        TS_WRITE_TX_WAIT    = 3'd5,
        TS_PROCESS_CMD      = 3'd6,
        TS_FLUSH_FRAME      = 3'd7
    } transport_state_t;

    typedef enum logic [1:0] {
        ES_IDLE           = 2'd0,
        ES_GPR_READ_DELAY = 2'd1,
        ES_MEM_WAIT       = 2'd2
    } exec_state_t;

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

    function automatic logic [31:0] payload_word_be(
        input logic [7:0] p0,
        input logic [7:0] p1,
        input logic [7:0] p2,
        input logic [7:0] p3
    );
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
endpackage : debug_uart_agent_pkg
