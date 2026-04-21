`timescale 1ns/1ps

module tb_debug_uart_claim;
    localparam int CLK_HALF_PERIOD_NS = 5;

    logic clk;
    logic rst;

    logic uart_req;
    logic uart_we;
    logic [31:0] uart_addr;
    logic [31:0] uart_wdata;
    logic [3:0] uart_sel;
    logic uart_ack;
    logic [31:0] uart_rdata;
    logic uart_err;

    logic halt_req;
    logic resume_req;
    logic step_req;
    logic [3:0] gpr_addr;
    logic [31:0] gpr_rdata;
    logic gpr_we;
    logic [31:0] gpr_wdata;

    logic dbg_mem_req;
    logic dbg_mem_we;
    logic [1:0] dbg_mem_size;
    logic [31:0] dbg_mem_addr;
    logic [31:0] dbg_mem_wdata;
    logic dbg_mem_done;
    logic [31:0] dbg_mem_rdata;
    logic dbg_mem_err;

    logic fw_rx_valid;
    logic [7:0] fw_rx_data;
    logic fw_rx_ready;

    logic fw_tx_valid;
    logic [7:0] fw_tx_data;
    logic fw_tx_ready;

    logic uart_owned;
    logic debug_active;

    // Host->agent RX bytes.
    logic [7:0] rx_fifo [0:127];
    integer rx_head;
    integer rx_tail;
    integer rx_count;

    // Agent->host TX bytes.
    logic [7:0] tx_fifo [0:255];
    integer tx_head;
    integer tx_tail;
    integer tx_count;

    // Agent->firmware forwarded RX bytes.
    logic [7:0] fwd_fifo [0:127];
    integer fwd_tail;
    integer fwd_count;

    logic req_d;
    logic req_d_prev;
    logic we_d;
    logic [31:0] addr_d;
    logic [31:0] wdata_d;

    int pass_count;
    int fail_count;

    localparam logic [7:0] SOF_REQ = 8'hA5;
    localparam logic [7:0] SOF_RESP = 8'h5A;

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

    task automatic check_true(input bit cond, input string msg);
        if (!cond) begin
            fail_count = fail_count + 1;
            $error("FAIL: %s", msg);
        end else begin
            pass_count = pass_count + 1;
        end
    endtask

    task automatic host_rx_push(input logic [7:0] b);
        begin
            rx_fifo[rx_tail] = b;
            rx_tail = (rx_tail + 1) % 128;
            rx_count = rx_count + 1;
        end
    endtask

    task automatic host_rx_push_hello_frame;
        logic [7:0] b0;
        logic [7:0] b1;
        logic [7:0] b2;
        logic [7:0] b3;
        logic [15:0] crc;
        begin
            b0 = SOF_REQ;
            b1 = 8'h11;
            b2 = 8'h00; // HELLO
            b3 = 8'h00; // LEN
            crc = 16'hFFFF;
            crc = crc16_update(crc, b0);
            crc = crc16_update(crc, b1);
            crc = crc16_update(crc, b2);
            crc = crc16_update(crc, b3);

            host_rx_push(b0);
            host_rx_push(b1);
            host_rx_push(b2);
            host_rx_push(b3);
            host_rx_push(crc[15:8]);
            host_rx_push(crc[7:0]);
        end
    endtask

    debug_uart_agent #(
        .BOOT_DEFAULT_ACTIVE(1'b1),
        .CLAIM_WINDOW_CYCLES(64),
        .MEM_TIMEOUT_CYCLES(64)
    ) dut (
        .clk                    (clk),
        .rst                    (rst),
        .uart_req_o             (uart_req),
        .uart_we_o              (uart_we),
        .uart_addr_o            (uart_addr),
        .uart_wdata_o           (uart_wdata),
        .uart_sel_o             (uart_sel),
        .uart_ack_i             (uart_ack),
        .uart_rdata_i           (uart_rdata),
        .uart_err_i             (uart_err),
        .core_halted_i          (1'b0),
        .core_halt_reason_i     (3'b000),
        .core_pc_i              (32'h0000_0000),
        .core_last_fault_i      (1'b0),
        .core_last_fault_pc_i   (32'h0000_0000),
        .core_last_fault_addr_i (32'h0000_0000),
        .core_last_illegal_inst_i(32'h0000_0000),
        .halt_req_o             (halt_req),
        .resume_req_o           (resume_req),
        .step_req_o             (step_req),
        .gpr_addr_o             (gpr_addr),
        .gpr_rdata_i            (gpr_rdata),
        .gpr_we_o               (gpr_we),
        .gpr_wdata_o            (gpr_wdata),
        .cycle_count_i          (32'h0000_0000),
        .retire_count_i         (32'h0000_0000),
        .branch_redirect_count_i(32'h0000_0000),
        .load_stall_count_i     (32'h0000_0000),
        .mem_stall_count_i      (32'h0000_0000),
        .dbg_mem_req_o          (dbg_mem_req),
        .dbg_mem_we_o           (dbg_mem_we),
        .dbg_mem_size_o         (dbg_mem_size),
        .dbg_mem_addr_o         (dbg_mem_addr),
        .dbg_mem_wdata_o        (dbg_mem_wdata),
        .dbg_mem_done_i         (dbg_mem_done),
        .dbg_mem_rdata_i        (dbg_mem_rdata),
        .dbg_mem_err_i          (dbg_mem_err),
        .fw_rx_valid_o          (fw_rx_valid),
        .fw_rx_data_o           (fw_rx_data),
        .fw_rx_ready_i          (fw_rx_ready),
        .fw_tx_valid_i          (fw_tx_valid),
        .fw_tx_data_i           (fw_tx_data),
        .fw_tx_ready_o          (fw_tx_ready),
        .uart_debug_owned_o     (uart_owned),
        .debug_active_o         (debug_active)
    );

    always begin
        #(CLK_HALF_PERIOD_NS) clk = ~clk;
    end

    // Physical UART MMIO backend model.
    always_ff @(posedge clk) begin
        uart_ack <= 1'b0;
        uart_err <= 1'b0;
        uart_rdata <= 32'h0000_0000;

        if (req_d && !req_d_prev) begin
            uart_ack <= 1'b1;
            if (!we_d) begin
                case (addr_d[7:0])
                    8'h08: begin // STATUS
                        uart_rdata[0] <= 1'b1; // TX ready always
                        uart_rdata[1] <= (rx_count != 0);
                    end
                    8'h04: begin // RXDATA
                        if (rx_count != 0) begin
                            uart_rdata[7:0] <= rx_fifo[rx_head];
                            rx_head <= (rx_head + 1) % 128;
                            rx_count <= rx_count - 1;
                        end
                    end
                    default: begin
                        uart_rdata <= 32'h0000_0000;
                    end
                endcase
            end else if (addr_d[7:0] == 8'h00) begin // TXDATA
                tx_fifo[tx_tail] <= wdata_d[7:0];
                tx_tail <= (tx_tail + 1) % 256;
                tx_count <= tx_count + 1;
            end
        end

        req_d_prev <= req_d;
        req_d <= uart_req;
        we_d <= uart_we;
        addr_d <= uart_addr;
        wdata_d <= uart_wdata;

        if (fw_rx_valid && fw_rx_ready) begin
            fwd_fifo[fwd_tail] <= fw_rx_data;
            fwd_tail <= (fwd_tail + 1) % 128;
            fwd_count <= fwd_count + 1;
        end

        if (fw_tx_ready && fw_tx_valid) begin
            fw_tx_valid <= 1'b0;
        end
    end

    initial begin
        logic [15:0] resp_crc_calc;

        clk = 1'b0;
        rst = 1'b1;
        gpr_rdata = 32'h0000_0000;
        dbg_mem_done = 1'b0;
        dbg_mem_rdata = 32'h0000_0000;
        dbg_mem_err = 1'b0;

        fw_rx_ready = 1'b1;
        fw_tx_valid = 1'b0;
        fw_tx_data = 8'h00;

        uart_ack = 1'b0;
        uart_rdata = 32'h0000_0000;
        uart_err = 1'b0;
        req_d = 1'b0;
        req_d_prev = 1'b0;
        we_d = 1'b0;
        addr_d = 32'h0000_0000;
        wdata_d = 32'h0000_0000;

        rx_head = 0;
        rx_tail = 0;
        rx_count = 0;
        tx_head = 0;
        tx_tail = 0;
        tx_count = 0;
        fwd_tail = 0;
        fwd_count = 0;

        pass_count = 0;
        fail_count = 0;

        repeat (4) @(posedge clk);
        rst <= 1'b0;

        // Scenario 1: plain console bytes are forwarded to firmware RX.
        host_rx_push(8'h61); // a
        host_rx_push(8'h62); // b
        host_rx_push(8'h63); // c
        repeat (200) @(posedge clk);

        check_true(fwd_count >= 3, "Non-debug bytes forwarded to firmware RX");
        check_true(fwd_fifo[0] == 8'h61, "Forwarded byte[0] matches");
        check_true(fwd_fifo[1] == 8'h62, "Forwarded byte[1] matches");
        check_true(fwd_fifo[2] == 8'h63, "Forwarded byte[2] matches");

        // Scenario 2: valid HELLO frame is consumed and answered, not forwarded.
        host_rx_push_hello_frame();
        repeat (400) @(posedge clk);

        check_true(tx_count >= 10, "HELLO response emitted on host TX");
        check_true(tx_fifo[0] == SOF_RESP, "HELLO response SOF matches");
        check_true(tx_fifo[1] == 8'h11, "HELLO response sequence echoed");
        check_true(tx_fifo[2] == 8'h00, "HELLO response status OK");
        check_true(tx_fifo[3] == 8'h04, "HELLO response payload length is 4");
        check_true(tx_fifo[4] == 8'h4E, "HELLO payload[0] N");
        check_true(tx_fifo[5] == 8'h43, "HELLO payload[1] C");
        check_true(tx_fifo[6] == 8'h44, "HELLO payload[2] D");
        check_true(tx_fifo[7] == 8'h42, "HELLO payload[3] B");

        resp_crc_calc = 16'hFFFF;
        resp_crc_calc = crc16_update(resp_crc_calc, tx_fifo[0]);
        resp_crc_calc = crc16_update(resp_crc_calc, tx_fifo[1]);
        resp_crc_calc = crc16_update(resp_crc_calc, tx_fifo[2]);
        resp_crc_calc = crc16_update(resp_crc_calc, tx_fifo[3]);
        resp_crc_calc = crc16_update(resp_crc_calc, tx_fifo[4]);
        resp_crc_calc = crc16_update(resp_crc_calc, tx_fifo[5]);
        resp_crc_calc = crc16_update(resp_crc_calc, tx_fifo[6]);
        resp_crc_calc = crc16_update(resp_crc_calc, tx_fifo[7]);
        check_true(tx_fifo[8] == resp_crc_calc[15:8] && tx_fifo[9] == resp_crc_calc[7:0], "HELLO response CRC matches");

        // Scenario 3: firmware TX byte is sent out to host.
        fw_tx_data = 8'h5A;
        fw_tx_valid = 1'b1;
        repeat (200) @(posedge clk);
        check_true(!fw_tx_valid, "Firmware TX byte accepted by ncdb");
        check_true(tx_count >= 11, "Firmware TX byte appears on host TX");
        check_true(tx_fifo[10] == 8'h5A, "Firmware TX byte value preserved");

        check_true(uart_owned, "ncdb always owns physical UART");

        $display("PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count != 0) begin
            $fatal(1, "tb_debug_uart_claim failed");
        end
        $finish;
    end
endmodule
