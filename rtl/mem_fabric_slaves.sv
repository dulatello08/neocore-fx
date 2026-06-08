module mem_fabric_slaves #(
    parameter bit INCLUDE_DEBUG = 1'b1
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        m_sel_debug,
    input  logic        m_we,
    input  logic [31:0] m_addr,
    input  logic [31:0] m_wdata,
    input  logic [3:0]  m_sel,
    input  logic        debug_enable_i,
    input  logic        core_halted_i,
    input  logic [31:0] core_current_pc_i,
    input  logic [2:0]  core_halt_reason_i,
    input  logic        core_last_fault_i,
    input  logic [31:0] core_last_fault_pc_i,
    input  logic [31:0] core_last_fault_addr_i,
    input  logic [31:0] core_last_illegal_inst_i,
    input  logic [31:0] core_cycle_count_i,
    input  logic [31:0] core_retire_count_i,
    input  logic [31:0] core_redirect_count_i,
    input  logic [31:0] core_load_stall_count_i,
    input  logic [31:0] core_mem_stall_count_i,
    input  logic [31:0] dbg_gpr_rdata_i,
    output logic        debugmmio_ack_o,
    output logic [31:0] debugmmio_rdata_o,
    output logic        debugmmio_err_o,
    output logic        mmio_halt_req_o,
    output logic        mmio_resume_req_o,
    output logic        mmio_step_req_o,
    output logic        mmio_pc_set_req_o,
    output logic [31:0] mmio_pc_set_data_o,
    output logic [3:0]  mmio_gpr_addr_o,
    output logic        mmio_gpr_we_o,
    output logic [31:0] mmio_gpr_wdata_o,
    output logic        mmio_dbg_mem_req_o,
    output logic        mmio_dbg_mem_we_o,
    output logic [1:0]  mmio_dbg_mem_size_o,
    output logic [31:0] mmio_dbg_mem_addr_o,
    output logic [31:0] mmio_dbg_mem_wdata_o,
    input  logic        mmio_dbg_mem_done_i,
    input  logic [31:0] mmio_dbg_mem_rdata_i,
    input  logic        mmio_dbg_mem_err_i,
    output logic        uart_halt_req_o,
    output logic        uart_resume_req_o,
    output logic        uart_step_req_o,
    output logic        uart_pc_set_req_o,
    output logic [31:0] uart_pc_set_data_o,
    output logic [3:0]  uart_gpr_addr_o,
    output logic        uart_gpr_we_o,
    output logic [31:0] uart_gpr_wdata_o,
    output logic        uart_dbg_mem_req_o,
    output logic        uart_dbg_mem_we_o,
    output logic [1:0]  uart_dbg_mem_size_o,
    output logic [31:0] uart_dbg_mem_addr_o,
    output logic [31:0] uart_dbg_mem_wdata_o,
    input  logic        uart_dbg_mem_done_i,
    input  logic [31:0] uart_dbg_mem_rdata_i,
    input  logic        uart_dbg_mem_err_i,
    output logic        uart_console_rx_valid_o,
    output logic [7:0]  uart_console_rx_data_o,
    input  logic        uart_console_rx_ready_i,
    input  logic        uart_console_tx_valid_i,
    input  logic [7:0]  uart_console_tx_data_i,
    output logic        uart_console_tx_ready_o,
    output logic        uart_debug_active_o,
    input  logic        uart_rx_i,
    input  logic        uart_console_pin_tx_i,
    output logic        uart_tx_o
);
    localparam logic [1:0] SIZE_WORD = 2'b10;
    logic debugmmio_req, debugmmio_we;
    logic [31:0] debugmmio_addr, debugmmio_wdata;
    logic [3:0] debugmmio_sel;
    logic uart_dbg_req, uart_dbg_we, uart_dbg_ack, uart_dbg_err;
    logic [31:0] uart_dbg_addr, uart_dbg_wdata, uart_dbg_rdata;
    logic [3:0] uart_dbg_sel;
    logic uart_phy_ack, uart_phy_err, uart_phy_pin_tx;
    logic [31:0] uart_phy_rdata;

    assign debugmmio_req = INCLUDE_DEBUG && m_sel_debug;
    assign debugmmio_we = m_we;
    assign debugmmio_addr = m_addr;
    assign debugmmio_wdata = m_wdata;
    assign debugmmio_sel = m_sel;

    generate
        if (INCLUDE_DEBUG) begin : g_debug
            debug_mmio u_debug_mmio (
                .clk(clk), .rst(rst), .req_i(debugmmio_req), .we_i(debugmmio_we),
                .addr_i(debugmmio_addr), .wdata_i(debugmmio_wdata), .sel_i(debugmmio_sel),
                .ack_o(debugmmio_ack_o), .rdata_o(debugmmio_rdata_o), .err_o(debugmmio_err_o),
                .core_halted_i(core_halted_i), .core_halt_reason_i(core_halt_reason_i), .core_pc_i(core_current_pc_i),
                .core_last_fault_i(core_last_fault_i), .core_last_fault_pc_i(core_last_fault_pc_i),
                .core_last_fault_addr_i(core_last_fault_addr_i), .core_last_illegal_inst_i(core_last_illegal_inst_i),
                .halt_req_o(mmio_halt_req_o), .resume_req_o(mmio_resume_req_o), .step_req_o(mmio_step_req_o),
                .pc_set_req_o(mmio_pc_set_req_o), .pc_set_data_o(mmio_pc_set_data_o),
                .gpr_addr_o(mmio_gpr_addr_o), .gpr_rdata_i(dbg_gpr_rdata_i), .gpr_we_o(mmio_gpr_we_o), .gpr_wdata_o(mmio_gpr_wdata_o),
                .cycle_count_i(core_cycle_count_i), .retire_count_i(core_retire_count_i), .branch_redirect_count_i(core_redirect_count_i),
                .load_stall_count_i(core_load_stall_count_i), .mem_stall_count_i(core_mem_stall_count_i),
                .dbg_mem_req_o(mmio_dbg_mem_req_o), .dbg_mem_we_o(mmio_dbg_mem_we_o), .dbg_mem_size_o(mmio_dbg_mem_size_o),
                .dbg_mem_addr_o(mmio_dbg_mem_addr_o), .dbg_mem_wdata_o(mmio_dbg_mem_wdata_o),
                .dbg_mem_done_i(mmio_dbg_mem_done_i), .dbg_mem_rdata_i(mmio_dbg_mem_rdata_i), .dbg_mem_err_i(mmio_dbg_mem_err_i)
            );

            debug_uart_agent u_debug_uart_agent (
                .clk(clk), .rst(rst), .uart_req_o(uart_dbg_req), .uart_we_o(uart_dbg_we), .uart_addr_o(uart_dbg_addr),
                .uart_wdata_o(uart_dbg_wdata), .uart_sel_o(uart_dbg_sel), .uart_ack_i(debug_enable_i ? uart_dbg_ack : 1'b0),
                .uart_rdata_i(debug_enable_i ? uart_dbg_rdata : 32'h0000_0000), .uart_err_i(debug_enable_i ? uart_dbg_err : 1'b0),
                .core_halted_i(core_halted_i), .core_halt_reason_i(core_halt_reason_i), .core_pc_i(core_current_pc_i),
                .core_last_fault_i(core_last_fault_i), .core_last_fault_pc_i(core_last_fault_pc_i),
                .core_last_fault_addr_i(core_last_fault_addr_i), .core_last_illegal_inst_i(core_last_illegal_inst_i),
                .halt_req_o(uart_halt_req_o), .resume_req_o(uart_resume_req_o), .step_req_o(uart_step_req_o),
                .pc_set_req_o(uart_pc_set_req_o), .pc_set_data_o(uart_pc_set_data_o),
                .gpr_addr_o(uart_gpr_addr_o), .gpr_rdata_i(dbg_gpr_rdata_i), .gpr_we_o(uart_gpr_we_o), .gpr_wdata_o(uart_gpr_wdata_o),
                .cycle_count_i(core_cycle_count_i), .retire_count_i(core_retire_count_i), .branch_redirect_count_i(core_redirect_count_i),
                .load_stall_count_i(core_load_stall_count_i), .mem_stall_count_i(core_mem_stall_count_i),
                .dbg_mem_req_o(uart_dbg_mem_req_o), .dbg_mem_we_o(uart_dbg_mem_we_o), .dbg_mem_size_o(uart_dbg_mem_size_o),
                .dbg_mem_addr_o(uart_dbg_mem_addr_o), .dbg_mem_wdata_o(uart_dbg_mem_wdata_o),
                .dbg_mem_done_i(uart_dbg_mem_done_i), .dbg_mem_rdata_i(uart_dbg_mem_rdata_i), .dbg_mem_err_i(uart_dbg_mem_err_i),
                .fw_rx_valid_o(uart_console_rx_valid_o), .fw_rx_data_o(uart_console_rx_data_o), .fw_rx_ready_i(debug_enable_i ? uart_console_rx_ready_i : 1'b0),
                .fw_tx_valid_i(debug_enable_i ? uart_console_tx_valid_i : 1'b0), .fw_tx_data_i(uart_console_tx_data_i), .fw_tx_ready_o(uart_console_tx_ready_o),
                .uart_debug_owned_o(), .debug_active_o(uart_debug_active_o)
            );

            uart_mmio #(.STREAM_MODE(1'b0)) u_uart_phy (
                .clk(clk), .rst(rst), .req_i(debug_enable_i && uart_dbg_req), .we_i(uart_dbg_we), .addr_i(uart_dbg_addr),
                .wdata_i(uart_dbg_wdata), .sel_i(uart_dbg_sel), .ack_o(uart_phy_ack), .rdata_o(uart_phy_rdata), .err_o(uart_phy_err),
                .uart_rx_i(uart_rx_i), .uart_tx_o(uart_phy_pin_tx), .stream_rx_valid_i(1'b0), .stream_rx_data_i(8'h00),
                .stream_rx_ready_o(), .stream_tx_valid_o(), .stream_tx_data_o(), .stream_tx_ready_i(1'b0)
            );
        end else begin : g_no_debug
            assign debugmmio_ack_o = 1'b0; assign debugmmio_rdata_o = 32'h0; assign debugmmio_err_o = 1'b0;
            assign mmio_halt_req_o = 1'b0; assign mmio_resume_req_o = 1'b0; assign mmio_step_req_o = 1'b0;
            assign mmio_pc_set_req_o = 1'b0; assign mmio_pc_set_data_o = 32'h0; assign mmio_gpr_addr_o = 4'h0;
            assign mmio_gpr_we_o = 1'b0; assign mmio_gpr_wdata_o = 32'h0; assign mmio_dbg_mem_req_o = 1'b0;
            assign mmio_dbg_mem_we_o = 1'b0; assign mmio_dbg_mem_size_o = SIZE_WORD; assign mmio_dbg_mem_addr_o = 32'h0; assign mmio_dbg_mem_wdata_o = 32'h0;
            assign uart_halt_req_o = 1'b0; assign uart_resume_req_o = 1'b0; assign uart_step_req_o = 1'b0;
            assign uart_pc_set_req_o = 1'b0; assign uart_pc_set_data_o = 32'h0; assign uart_gpr_addr_o = 4'h0;
            assign uart_gpr_we_o = 1'b0; assign uart_gpr_wdata_o = 32'h0; assign uart_dbg_mem_req_o = 1'b0;
            assign uart_dbg_mem_we_o = 1'b0; assign uart_dbg_mem_size_o = SIZE_WORD; assign uart_dbg_mem_addr_o = 32'h0; assign uart_dbg_mem_wdata_o = 32'h0;
            assign uart_debug_active_o = 1'b0; assign uart_console_rx_valid_o = 1'b0; assign uart_console_rx_data_o = 8'h00; assign uart_console_tx_ready_o = 1'b0;
            assign uart_phy_ack = 1'b0; assign uart_phy_rdata = 32'h0; assign uart_phy_err = 1'b0; assign uart_phy_pin_tx = 1'b1;
        end
    endgenerate

    assign uart_tx_o = INCLUDE_DEBUG ? uart_phy_pin_tx : uart_console_pin_tx_i;
    assign uart_dbg_ack = uart_phy_ack;
    assign uart_dbg_rdata = uart_phy_rdata;
    assign uart_dbg_err = uart_phy_err;
endmodule
