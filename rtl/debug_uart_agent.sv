module debug_uart_agent #(
    parameter bit          BOOT_DEFAULT_ACTIVE = 1'b1,
    parameter int unsigned CLAIM_WINDOW_CYCLES = 400_000_000,
    parameter int unsigned MEM_TIMEOUT_CYCLES = 4096
) (
    input  logic        clk,
    input  logic        rst,

    output logic        uart_req_o,
    output logic        uart_we_o,
    output logic [31:0] uart_addr_o,
    output logic [31:0] uart_wdata_o,
    output logic [3:0]  uart_sel_o,
    input  logic        uart_ack_i,
    input  logic [31:0] uart_rdata_i,
    input  logic        uart_err_i,

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

    logic       cmd_valid;
    logic       cmd_ready;
    logic [7:0] cmd_seq;
    logic [7:0] cmd_id;
    logic [7:0] cmd_len;
    logic [7:0] cmd_payload [0:31];

    logic       resp_valid;
    logic [7:0] resp_seq;
    logic [7:0] resp_status;
    logic [7:0] resp_len;
    logic [7:0] resp_payload [0:31];

    logic       exec_busy;

    debug_uart_agent_transport u_transport (
        .clk            (clk),
        .rst            (rst),
        .uart_req_o     (uart_req_o),
        .uart_we_o      (uart_we_o),
        .uart_addr_o    (uart_addr_o),
        .uart_wdata_o   (uart_wdata_o),
        .uart_sel_o     (uart_sel_o),
        .uart_ack_i     (uart_ack_i),
        .uart_rdata_i   (uart_rdata_i),
        .uart_err_i     (uart_err_i),
        .fw_rx_valid_o  (fw_rx_valid_o),
        .fw_rx_data_o   (fw_rx_data_o),
        .fw_rx_ready_i  (fw_rx_ready_i),
        .fw_tx_valid_i  (fw_tx_valid_i),
        .fw_tx_data_i   (fw_tx_data_i),
        .fw_tx_ready_o  (fw_tx_ready_o),
        .cmd_valid_o    (cmd_valid),
        .cmd_seq_o      (cmd_seq),
        .cmd_id_o       (cmd_id),
        .cmd_len_o      (cmd_len),
        .cmd_payload_o  (cmd_payload),
        .cmd_ready_i    (cmd_ready),
        .resp_valid_i   (resp_valid),
        .resp_seq_i     (resp_seq),
        .resp_status_i  (resp_status),
        .resp_len_i     (resp_len),
        .resp_payload_i (resp_payload),
        .exec_busy_i    (exec_busy),
        .debug_active_o (debug_active_o)
    );

    debug_uart_agent_executor #(
        .MEM_TIMEOUT_CYCLES(MEM_TIMEOUT_CYCLES)
    ) u_executor (
        .clk                        (clk),
        .rst                        (rst),
        .cmd_valid_i                (cmd_valid),
        .cmd_seq_i                  (cmd_seq),
        .cmd_id_i                   (cmd_id),
        .cmd_len_i                  (cmd_len),
        .cmd_payload_i              (cmd_payload),
        .cmd_ready_o                (cmd_ready),
        .core_halted_i              (core_halted_i),
        .core_halt_reason_i         (core_halt_reason_i),
        .core_pc_i                  (core_pc_i),
        .core_last_fault_i          (core_last_fault_i),
        .core_last_fault_pc_i       (core_last_fault_pc_i),
        .core_last_fault_addr_i     (core_last_fault_addr_i),
        .core_last_illegal_inst_i   (core_last_illegal_inst_i),
        .halt_req_o                 (halt_req_o),
        .resume_req_o               (resume_req_o),
        .step_req_o                 (step_req_o),
        .pc_set_req_o               (pc_set_req_o),
        .pc_set_data_o              (pc_set_data_o),
        .gpr_addr_o                 (gpr_addr_o),
        .gpr_rdata_i                (gpr_rdata_i),
        .gpr_we_o                   (gpr_we_o),
        .gpr_wdata_o                (gpr_wdata_o),
        .cycle_count_i              (cycle_count_i),
        .retire_count_i             (retire_count_i),
        .branch_redirect_count_i    (branch_redirect_count_i),
        .load_stall_count_i         (load_stall_count_i),
        .mem_stall_count_i          (mem_stall_count_i),
        .dbg_mem_req_o              (dbg_mem_req_o),
        .dbg_mem_we_o               (dbg_mem_we_o),
        .dbg_mem_size_o             (dbg_mem_size_o),
        .dbg_mem_addr_o             (dbg_mem_addr_o),
        .dbg_mem_wdata_o            (dbg_mem_wdata_o),
        .dbg_mem_done_i             (dbg_mem_done_i),
        .dbg_mem_rdata_i            (dbg_mem_rdata_i),
        .dbg_mem_err_i              (dbg_mem_err_i),
        .resp_valid_o               (resp_valid),
        .resp_seq_o                 (resp_seq),
        .resp_status_o              (resp_status),
        .resp_len_o                 (resp_len),
        .resp_payload_o             (resp_payload),
        .busy_o                     (exec_busy)
    );

    assign uart_debug_owned_o = 1'b1;

    logic unused_claim;
    assign unused_claim = BOOT_DEFAULT_ACTIVE
                        ^ CLAIM_WINDOW_CYCLES[0]
                        ^ core_last_fault_addr_i[0]
                        ^ core_last_illegal_inst_i[0];
endmodule : debug_uart_agent
