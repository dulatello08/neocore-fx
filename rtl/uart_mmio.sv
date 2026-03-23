//
// uart_mmio.sv
// NeoCoreFX - Simple MMIO UART (TX serializer + register block)
//

module uart_mmio (
    input  logic        clk,
    input  logic        rst,

    input  logic        req_i,
    input  logic        we_i,
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic [3:0]  sel_i,

    output logic        ack_o,
    output logic [31:0] rdata_o,
    output logic        err_o,

    input  logic        uart_rx_i,
    output logic        uart_tx_o
);
    timeunit 1ns;
    timeprecision 1ps;

    import mem_pkg::*;

    localparam int unsigned TX_FIFO_DEPTH = 16;
    localparam int unsigned TX_FIFO_PTR_W = $clog2(TX_FIFO_DEPTH);
    localparam int unsigned TX_FIFO_COUNT_W = $clog2(TX_FIFO_DEPTH + 1);

    localparam logic [5:0] UART_REG_TXDATA  = UART_TXDATA_OFFSET[7:2];
    localparam logic [5:0] UART_REG_RXDATA  = UART_RXDATA_OFFSET[7:2];
    localparam logic [5:0] UART_REG_STATUS  = UART_STATUS_OFFSET[7:2];
    localparam logic [5:0] UART_REG_CTRL    = UART_CTRL_OFFSET[7:2];
    localparam logic [5:0] UART_REG_BAUDDIV = UART_BAUDDIV_OFFSET[7:2];

`ifdef SYNTHESIS
    localparam logic [31:0] UART_BAUDDIV_RESET = 32'd217;
`else
    // Faster default for simulation so benchmark logging does not dominate runtime.
    localparam logic [31:0] UART_BAUDDIV_RESET = 32'd8;
`endif

    logic [31:0] ctrl_q;
    logic [31:0] bauddiv_q;
    logic        tx_overrun_q;
    logic        rx_overrun_q;

    logic [7:0] tx_fifo [0:TX_FIFO_DEPTH-1];
    logic [TX_FIFO_PTR_W-1:0] tx_wr_ptr_q;
    logic [TX_FIFO_PTR_W-1:0] tx_rd_ptr_q;
    logic [TX_FIFO_COUNT_W-1:0] tx_count_q;

    logic        tx_active_q;
    logic [9:0]  tx_shift_q;
    logic [3:0]  tx_bit_idx_q;
    logic [31:0] tx_baud_cnt_q;

    logic        rx_valid_q;
    logic [7:0]  rx_data_q;

    logic        req_valid_q;
    logic        req_we_q;
    logic [31:0] req_addr_q;
    logic [31:0] req_wdata_q;
    logic [3:0]  req_sel_q;
    logic        req_wait_release_q;
    logic        req_wait_cycle_q;

    function automatic logic [7:0] pick_lowest_sel_byte(
        input logic [31:0] data,
        input logic [3:0]  sel
    );
        begin
            if (sel[0]) begin
                return data[7:0];
            end
            if (sel[1]) begin
                return data[15:8];
            end
            if (sel[2]) begin
                return data[23:16];
            end
            return data[31:24];
        end
    endfunction

    assign uart_tx_o = tx_active_q ? tx_shift_q[tx_bit_idx_q] : 1'b1;

    // RX serial sampler is not implemented yet; keep input explicitly consumed.
    logic unused_uart_rx;
    assign unused_uart_rx = uart_rx_i;

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!rst
         && !tx_active_q
         && ctrl_q[0]
         && (tx_count_q != 0)
         && $test$plusargs("UART_STDOUT")) begin
            $write("%c", tx_fifo[tx_rd_ptr_q]);
        end
    end
`endif

    always_ff @(posedge clk) begin
        logic [TX_FIFO_PTR_W-1:0] tx_wr_ptr_n;
        logic [TX_FIFO_PTR_W-1:0] tx_rd_ptr_n;
        logic [TX_FIFO_COUNT_W-1:0] tx_count_n;
        logic        tx_active_n;
        logic [9:0]  tx_shift_n;
        logic [3:0]  tx_bit_idx_n;
        logic [31:0] tx_baud_cnt_n;

        logic [31:0] ctrl_n;
        logic [31:0] bauddiv_n;
        logic        tx_overrun_n;
        logic        rx_overrun_n;
        logic        rx_valid_n;
        logic [7:0]  rx_data_n;

        logic        req_valid_n;
        logic        req_we_n;
        logic [31:0] req_addr_n;
        logic [31:0] req_wdata_n;
        logic [3:0]  req_sel_n;
        logic        req_wait_release_n;
        logic        req_wait_cycle_n;

        logic        ack_n;
        logic        err_n;
        logic [31:0] rdata_n;

        logic [31:0] bauddiv_eff;
        logic [5:0]  reg_index;
        logic [7:0]  wr_byte;
        logic        req_diff_from_last;

        if (rst) begin
            ctrl_q <= 32'h0000_0003;
            bauddiv_q <= UART_BAUDDIV_RESET;
            tx_overrun_q <= 1'b0;
            rx_overrun_q <= 1'b0;

            tx_wr_ptr_q <= '0;
            tx_rd_ptr_q <= '0;
            tx_count_q <= '0;
            tx_active_q <= 1'b0;
            tx_shift_q <= 10'h3FF;
            tx_bit_idx_q <= 4'd0;
            tx_baud_cnt_q <= 32'd0;

            rx_valid_q <= 1'b0;
            rx_data_q <= 8'h00;

            req_valid_q <= 1'b0;
            req_we_q <= 1'b0;
            req_addr_q <= 32'h0000_0000;
            req_wdata_q <= 32'h0000_0000;
            req_sel_q <= 4'b0000;
            req_wait_release_q <= 1'b0;
            req_wait_cycle_q <= 1'b0;

            ack_o <= 1'b0;
            err_o <= 1'b0;
            rdata_o <= 32'h0000_0000;
        end else begin
            tx_wr_ptr_n = tx_wr_ptr_q;
            tx_rd_ptr_n = tx_rd_ptr_q;
            tx_count_n = tx_count_q;
            tx_active_n = tx_active_q;
            tx_shift_n = tx_shift_q;
            tx_bit_idx_n = tx_bit_idx_q;
            tx_baud_cnt_n = tx_baud_cnt_q;

            ctrl_n = ctrl_q;
            bauddiv_n = bauddiv_q;
            tx_overrun_n = tx_overrun_q;
            rx_overrun_n = rx_overrun_q;
            rx_valid_n = rx_valid_q;
            rx_data_n = rx_data_q;

            req_valid_n = req_valid_q;
            req_we_n = req_we_q;
            req_addr_n = req_addr_q;
            req_wdata_n = req_wdata_q;
            req_sel_n = req_sel_q;
            req_wait_release_n = req_wait_release_q;
            req_wait_cycle_n = req_wait_cycle_q;

            ack_n = 1'b0;
            err_n = 1'b0;
            rdata_n = 32'h0000_0000;

            bauddiv_eff = (bauddiv_q == 32'd0) ? 32'd1 : bauddiv_q;

            // TX engine consumes one FIFO byte whenever idle and enabled.
            if (tx_active_q) begin
                if (tx_baud_cnt_q >= bauddiv_eff) begin
                    tx_baud_cnt_n = 32'd0;
                    if (tx_bit_idx_q == 4'd9) begin
                        tx_active_n = 1'b0;
                        tx_bit_idx_n = 4'd0;
                    end else begin
                        tx_bit_idx_n = tx_bit_idx_q + 4'd1;
                    end
                end else begin
                    tx_baud_cnt_n = tx_baud_cnt_q + 32'd1;
                end
            end else begin
                tx_baud_cnt_n = 32'd0;
                if (ctrl_q[0] && (tx_count_q != 0)) begin
                    logic [7:0] tx_launch_byte;
                    tx_launch_byte = tx_fifo[tx_rd_ptr_q];
                    tx_active_n = 1'b1;
                    tx_shift_n = {1'b1, tx_launch_byte, 1'b0};
                    tx_bit_idx_n = 4'd0;
                    tx_rd_ptr_n = tx_rd_ptr_q + 1'b1;
                    tx_count_n = tx_count_q - 1'b1;
                end
            end

            req_diff_from_last = (we_i != req_we_q)
                              || (addr_i != req_addr_q)
                              || (wdata_i != req_wdata_q)
                              || (sel_i != req_sel_q);

            // Replay-hold timeout:
            // - hold for one cycle after completion while req_i stays high
            // - if master still does not change request, release on next cycle
            //   to avoid deadlock on identical consecutive writes
            if (req_wait_release_q) begin
                if (!req_i) begin
                    req_wait_release_n = 1'b0;
                    req_wait_cycle_n = 1'b0;
                end else if (!req_wait_cycle_q) begin
                    req_wait_cycle_n = 1'b1;
                end else begin
                    req_wait_release_n = 1'b0;
                    req_wait_cycle_n = 1'b0;
                end
            end

            // Latch one bus request at a time.
            if (!req_valid_n && req_i
             && (!req_wait_release_n || req_diff_from_last)) begin
                req_valid_n = 1'b1;
                req_we_n = we_i;
                req_addr_n = addr_i;
                req_wdata_n = wdata_i;
                req_sel_n = sel_i;
            end

            if (req_valid_n) begin
                reg_index = req_addr_n[7:2];
                wr_byte = pick_lowest_sel_byte(req_wdata_n, req_sel_n);

                case (reg_index)
                    UART_REG_TXDATA: begin
                        if (req_we_n) begin
                            if (|req_sel_n) begin
                                if (!ctrl_n[0]) begin
                                    // TX disabled: consume write as no-op.
                                    ack_n = 1'b1;
                                    req_valid_n = 1'b0;
                                    req_wait_release_n = 1'b1;
                                    req_wait_cycle_n = 1'b0;
                                end else if (tx_count_n < TX_FIFO_DEPTH) begin
                                    tx_fifo[tx_wr_ptr_n] <= wr_byte;
                                    tx_wr_ptr_n = tx_wr_ptr_n + 1'b1;
                                    tx_count_n = tx_count_n + 1'b1;
                                    ack_n = 1'b1;
                                    req_valid_n = 1'b0;
                                    req_wait_release_n = 1'b1;
                                    req_wait_cycle_n = 1'b0;
                                end else begin
                                    // FIFO full: hold request and stall until space is available.
                                end
                            end else begin
                                ack_n = 1'b1;
                                req_valid_n = 1'b0;
                                req_wait_release_n = 1'b1;
                                req_wait_cycle_n = 1'b0;
                            end
                        end else begin
                            rdata_n = 32'h0000_0000;
                            ack_n = 1'b1;
                            req_valid_n = 1'b0;
                            req_wait_release_n = 1'b1;
                            req_wait_cycle_n = 1'b0;
                        end
                    end

                    UART_REG_RXDATA: begin
                        if (req_we_n) begin
                            if (|req_sel_n) begin
                                if (!ctrl_n[1]) begin
                                    // RX disabled: drop silently.
                                end else if (rx_valid_n) begin
                                    rx_overrun_n = 1'b1;
                                end else begin
                                    rx_data_n = wr_byte;
                                    rx_valid_n = 1'b1;
                                end
                            end
                            ack_n = 1'b1;
                            req_valid_n = 1'b0;
                            req_wait_release_n = 1'b1;
                            req_wait_cycle_n = 1'b0;
                        end else begin
                            if (rx_valid_n) begin
                                rdata_n = {4{rx_data_n}};
                                rx_valid_n = 1'b0;
                            end
                            ack_n = 1'b1;
                            req_valid_n = 1'b0;
                            req_wait_release_n = 1'b1;
                            req_wait_cycle_n = 1'b0;
                        end
                    end

                    UART_REG_STATUS: begin
                        if (req_we_n) begin
                            logic [31:0] status_write;
                            status_write = mem_apply_write_sel(32'h0000_0000, req_wdata_n, req_sel_n);
                            if (status_write[2]) begin
                                tx_overrun_n = 1'b0;
                            end
                            if (status_write[3]) begin
                                rx_overrun_n = 1'b0;
                            end
                        end else begin
                            rdata_n = {28'h0000000, rx_overrun_n, tx_overrun_n,
                                       rx_valid_n, (tx_count_n < TX_FIFO_DEPTH)};
                        end
                        ack_n = 1'b1;
                        req_valid_n = 1'b0;
                        req_wait_release_n = 1'b1;
                        req_wait_cycle_n = 1'b0;
                    end

                    UART_REG_CTRL: begin
                        if (req_we_n) begin
                            ctrl_n = mem_apply_write_sel(ctrl_n, req_wdata_n, req_sel_n);
                        end else begin
                            rdata_n = ctrl_n;
                        end
                        ack_n = 1'b1;
                        req_valid_n = 1'b0;
                        req_wait_release_n = 1'b1;
                        req_wait_cycle_n = 1'b0;
                    end

                    UART_REG_BAUDDIV: begin
                        if (req_we_n) begin
                            bauddiv_n = mem_apply_write_sel(bauddiv_n, req_wdata_n, req_sel_n);
                        end else begin
                            rdata_n = bauddiv_n;
                        end
                        ack_n = 1'b1;
                        req_valid_n = 1'b0;
                        req_wait_release_n = 1'b1;
                        req_wait_cycle_n = 1'b0;
                    end

                    default: begin
                        err_n = 1'b1;
                        req_valid_n = 1'b0;
                        req_wait_release_n = 1'b1;
                        req_wait_cycle_n = 1'b0;
                    end
                endcase
            end

            tx_wr_ptr_q <= tx_wr_ptr_n;
            tx_rd_ptr_q <= tx_rd_ptr_n;
            tx_count_q <= tx_count_n;
            tx_active_q <= tx_active_n;
            tx_shift_q <= tx_shift_n;
            tx_bit_idx_q <= tx_bit_idx_n;
            tx_baud_cnt_q <= tx_baud_cnt_n;

            ctrl_q <= ctrl_n;
            bauddiv_q <= bauddiv_n;
            tx_overrun_q <= tx_overrun_n;
            rx_overrun_q <= rx_overrun_n;
            rx_valid_q <= rx_valid_n;
            rx_data_q <= rx_data_n;

            req_valid_q <= req_valid_n;
            req_we_q <= req_we_n;
            req_addr_q <= req_addr_n;
            req_wdata_q <= req_wdata_n;
            req_sel_q <= req_sel_n;
            req_wait_release_q <= req_wait_release_n;
            req_wait_cycle_q <= req_wait_cycle_n;

            ack_o <= ack_n;
            err_o <= err_n;
            rdata_o <= rdata_n;
        end
    end
endmodule : uart_mmio
