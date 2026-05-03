module debug_uart_agent_executor #(
    parameter int unsigned MEM_TIMEOUT_CYCLES = 4096
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        cmd_valid_i,
    input  logic [7:0]  cmd_seq_i,
    input  logic [7:0]  cmd_id_i,
    input  logic [7:0]  cmd_len_i,
    input  logic [7:0]  cmd_payload_i [0:31],
    output logic        cmd_ready_o,
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
    output logic        resp_valid_o,
    output logic [7:0]  resp_seq_o,
    output logic [7:0]  resp_status_o,
    output logic [7:0]  resp_len_o,
    output logic [7:0]  resp_payload_o [0:31],
    output logic        busy_o
);
    timeunit 1ns;
    timeprecision 1ps;
    import debug_uart_agent_pkg::*;
    exec_state_t state_q;
    logic [7:0] cmd_seq_q;
    logic mem_start_q;
    logic mem_is_read_q;
    logic mem_is_burst_q;
    logic mem_burst_is_set_q;
    logic [31:0] mem_addr_q;
    logic [31:0] mem_wdata_q;
    logic [1:0] mem_size_q;
    logic [7:0] mem_burst_count_q;
    logic mem_done_valid;
    logic [7:0] mem_done_status;
    logic [7:0] mem_done_len;
    logic [7:0] mem_done_payload [0:31];
    integer i;
    assign cmd_ready_o = (state_q == ES_IDLE);
    assign busy_o = (state_q != ES_IDLE);
    task automatic emit_no_payload(input logic [7:0] seq, input logic [7:0] status);
        begin
            resp_seq_o <= seq;
            resp_status_o <= status;
            resp_len_o <= 8'd0;
            resp_valid_o <= 1'b1;
        end
    endtask
    task automatic emit_word(input logic [7:0] seq, input logic [7:0] status, input logic [31:0] word);
        begin
            resp_seq_o <= seq;
            resp_status_o <= status;
            resp_len_o <= 8'd4;
            resp_payload_o[0] <= word[31:24];
            resp_payload_o[1] <= word[23:16];
            resp_payload_o[2] <= word[15:8];
            resp_payload_o[3] <= word[7:0];
            resp_valid_o <= 1'b1;
        end
    endtask
    task automatic emit_words5(
        input logic [7:0] seq, input logic [7:0] status, input logic [31:0] w0, input logic [31:0] w1,
        input logic [31:0] w2, input logic [31:0] w3, input logic [31:0] w4
    );
        begin
            resp_seq_o <= seq;
            resp_status_o <= status;
            resp_len_o <= 8'd20;
            resp_payload_o[0]  <= w0[31:24];
            resp_payload_o[1]  <= w0[23:16];
            resp_payload_o[2]  <= w0[15:8];
            resp_payload_o[3]  <= w0[7:0];
            resp_payload_o[4]  <= w1[31:24];
            resp_payload_o[5]  <= w1[23:16];
            resp_payload_o[6]  <= w1[15:8];
            resp_payload_o[7]  <= w1[7:0];
            resp_payload_o[8]  <= w2[31:24];
            resp_payload_o[9]  <= w2[23:16];
            resp_payload_o[10] <= w2[15:8];
            resp_payload_o[11] <= w2[7:0];
            resp_payload_o[12] <= w3[31:24];
            resp_payload_o[13] <= w3[23:16];
            resp_payload_o[14] <= w3[15:8];
            resp_payload_o[15] <= w3[7:0];
            resp_payload_o[16] <= w4[31:24];
            resp_payload_o[17] <= w4[23:16];
            resp_payload_o[18] <= w4[15:8];
            resp_payload_o[19] <= w4[7:0];
            resp_valid_o <= 1'b1;
        end
    endtask
    debug_uart_agent_memops #(
        .MEM_TIMEOUT_CYCLES(MEM_TIMEOUT_CYCLES)
    ) u_memops (
        .clk            (clk),
        .rst            (rst),
        .start_i        (mem_start_q),
        .is_read_i      (mem_is_read_q),
        .is_burst_i     (mem_is_burst_q),
        .burst_is_set_i (mem_burst_is_set_q),
        .addr_i         (mem_addr_q),
        .wdata_i        (mem_wdata_q),
        .size_i         (mem_size_q),
        .burst_count_i  (mem_burst_count_q),
        .busy_o         (),
        .done_valid_o   (mem_done_valid),
        .done_status_o  (mem_done_status),
        .done_len_o     (mem_done_len),
        .done_payload_o (mem_done_payload),
        .dbg_mem_req_o  (dbg_mem_req_o),
        .dbg_mem_we_o   (dbg_mem_we_o),
        .dbg_mem_size_o (dbg_mem_size_o),
        .dbg_mem_addr_o (dbg_mem_addr_o),
        .dbg_mem_wdata_o(dbg_mem_wdata_o),
        .dbg_mem_done_i (dbg_mem_done_i),
        .dbg_mem_rdata_i(dbg_mem_rdata_i),
        .dbg_mem_err_i  (dbg_mem_err_i)
    );
    always_ff @(posedge clk) begin
        logic [31:0] mem_addr_word;
        logic [31:0] mem_data_word;
        logic [1:0] mem_size_field;
        logic [31:0] status_payload_word;
        halt_req_o <= 1'b0;
        resume_req_o <= 1'b0;
        step_req_o <= 1'b0;
        pc_set_req_o <= 1'b0;
        gpr_we_o <= 1'b0;
        resp_valid_o <= 1'b0;
        mem_start_q <= 1'b0;
        if (rst) begin
            state_q <= ES_IDLE;
            cmd_seq_q <= 8'h00;
            mem_is_read_q <= 1'b0;
            mem_is_burst_q <= 1'b0;
            mem_burst_is_set_q <= 1'b0;
            mem_addr_q <= 32'h0000_0000;
            mem_wdata_q <= 32'h0000_0000;
            mem_size_q <= SIZE_WORD;
            mem_burst_count_q <= 8'd0;
            pc_set_data_o <= 32'h0000_0000;
            gpr_addr_o <= 4'h0;
            gpr_wdata_o <= 32'h0000_0000;
            resp_seq_o <= 8'h00;
            resp_status_o <= 8'h00;
            resp_len_o <= 8'd0;
            for (i = 0; i < 32; i = i + 1) begin
                resp_payload_o[i] <= 8'h00;
            end
        end else begin
            case (state_q)
                ES_IDLE: begin
                    if (cmd_valid_i) begin
                        cmd_seq_q <= cmd_seq_i;
                        case (cmd_id_i)
                            CMD_HELLO: emit_word(cmd_seq_i, ST_OK, 32'h4E43_4442);
                            CMD_CLAIM: emit_no_payload(cmd_seq_i, ST_OK);
                            CMD_RELEASE: emit_no_payload(cmd_seq_i, ST_OK);
                            CMD_HALT: begin
                                halt_req_o <= 1'b1;
                                emit_no_payload(cmd_seq_i, ST_OK);
                            end
                            CMD_RESUME: begin
                                resume_req_o <= 1'b1;
                                emit_no_payload(cmd_seq_i, ST_OK);
                            end
                            CMD_STEP: begin
                                step_req_o <= 1'b1;
                                emit_no_payload(cmd_seq_i, ST_OK);
                            end
                            CMD_SET_PC: begin
                                if (cmd_len_i != 8'd4) begin
                                    emit_no_payload(cmd_seq_i, ST_BAD_CMD);
                                end else if (!core_halted_i) begin
                                    emit_no_payload(cmd_seq_i, ST_NOT_HALTED);
                                end else begin
                                    pc_set_data_o <= payload_word_be(cmd_payload_i[0], cmd_payload_i[1],
                                                                      cmd_payload_i[2], cmd_payload_i[3]);
                                    pc_set_req_o <= 1'b1;
                                    emit_no_payload(cmd_seq_i, ST_OK);
                                end
                            end
                            CMD_READ_STATUS: begin
                                status_payload_word = {
                                    24'h000000,
                                    core_last_fault_i,
                                    core_halt_reason_i,
                                    3'b000,
                                    core_halted_i
                                };
                                emit_words5(cmd_seq_i, ST_OK, status_payload_word, core_pc_i, core_last_fault_pc_i,
                                            core_last_fault_addr_i, core_last_illegal_inst_i);
                            end
                            CMD_READ_GPR: begin
                                if (cmd_len_i != 8'd1) begin
                                    emit_no_payload(cmd_seq_i, ST_BAD_CMD);
                                end else begin
                                    gpr_addr_o <= cmd_payload_i[0][3:0];
                                    state_q <= ES_GPR_READ_DELAY;
                                end
                            end
                            CMD_WRITE_GPR: begin
                                if (cmd_len_i != 8'd5) begin
                                    emit_no_payload(cmd_seq_i, ST_BAD_CMD);
                                end else if (!core_halted_i) begin
                                    emit_no_payload(cmd_seq_i, ST_NOT_HALTED);
                                end else begin
                                    gpr_addr_o <= cmd_payload_i[0][3:0];
                                    gpr_wdata_o <= payload_word_be(cmd_payload_i[1], cmd_payload_i[2],
                                                                   cmd_payload_i[3], cmd_payload_i[4]);
                                    gpr_we_o <= 1'b1;
                                    emit_no_payload(cmd_seq_i, ST_OK);
                                end
                            end
                            CMD_READ_MEM: begin
                                if (cmd_len_i != 8'd5) begin
                                    emit_no_payload(cmd_seq_i, ST_BAD_CMD);
                                end else if (!core_halted_i) begin
                                    emit_no_payload(cmd_seq_i, ST_NOT_HALTED);
                                end else begin
                                    mem_addr_word = payload_word_be(cmd_payload_i[0], cmd_payload_i[1],
                                                                     cmd_payload_i[2], cmd_payload_i[3]);
                                    mem_size_field = cmd_payload_i[4][1:0];
                                    mem_is_read_q <= 1'b1;
                                    mem_is_burst_q <= 1'b0;
                                    mem_burst_is_set_q <= 1'b0;
                                    mem_addr_q <= mem_addr_word;
                                    mem_wdata_q <= 32'h0000_0000;
                                    mem_size_q <= (mem_size_field == 2'b00) ? SIZE_BYTE
                                               : (mem_size_field == 2'b01) ? SIZE_HALF
                                               : SIZE_WORD;
                                    mem_burst_count_q <= 8'd0;
                                    mem_start_q <= 1'b1;
                                    state_q <= ES_MEM_WAIT;
                                end
                            end
                            CMD_WRITE_MEM: begin
                                if (cmd_len_i != 8'd9) begin
                                    emit_no_payload(cmd_seq_i, ST_BAD_CMD);
                                end else if (!core_halted_i) begin
                                    emit_no_payload(cmd_seq_i, ST_NOT_HALTED);
                                end else begin
                                    mem_addr_word = payload_word_be(cmd_payload_i[0], cmd_payload_i[1],
                                                                     cmd_payload_i[2], cmd_payload_i[3]);
                                    mem_size_field = cmd_payload_i[4][1:0];
                                    mem_data_word = payload_word_be(cmd_payload_i[5], cmd_payload_i[6],
                                                                     cmd_payload_i[7], cmd_payload_i[8]);
                                    mem_is_read_q <= 1'b0;
                                    mem_is_burst_q <= 1'b0;
                                    mem_burst_is_set_q <= 1'b0;
                                    mem_addr_q <= mem_addr_word;
                                    mem_wdata_q <= mem_data_word;
                                    mem_size_q <= (mem_size_field == 2'b00) ? SIZE_BYTE
                                               : (mem_size_field == 2'b01) ? SIZE_HALF
                                               : SIZE_WORD;
                                    mem_burst_count_q <= 8'd0;
                                    mem_start_q <= 1'b1;
                                    state_q <= ES_MEM_WAIT;
                                end
                            end
                            CMD_READ_COUNTERS: begin
                                emit_words5(cmd_seq_i, ST_OK, cycle_count_i, retire_count_i,
                                            branch_redirect_count_i, load_stall_count_i, mem_stall_count_i);
                            end
                            CMD_READ_MEM_BURST: begin
                                if (cmd_len_i != 8'd6) begin
                                    emit_no_payload(cmd_seq_i, ST_BAD_CMD);
                                end else if (!core_halted_i) begin
                                    emit_no_payload(cmd_seq_i, ST_NOT_HALTED);
                                end else if ((cmd_payload_i[5] == 8'd0) || (cmd_payload_i[5] > 8'd8)) begin
                                    emit_no_payload(cmd_seq_i, ST_BAD_CMD);
                                end else begin
                                    mem_addr_word = payload_word_be(cmd_payload_i[0], cmd_payload_i[1],
                                                                     cmd_payload_i[2], cmd_payload_i[3]);
                                    mem_size_field = cmd_payload_i[4][1:0];
                                    mem_is_read_q <= 1'b1;
                                    mem_is_burst_q <= 1'b1;
                                    mem_burst_is_set_q <= 1'b0;
                                    mem_addr_q <= mem_addr_word;
                                    mem_wdata_q <= 32'h0000_0000;
                                    mem_size_q <= (mem_size_field == 2'b00) ? SIZE_BYTE
                                               : (mem_size_field == 2'b01) ? SIZE_HALF
                                               : SIZE_WORD;
                                    mem_burst_count_q <= cmd_payload_i[5];
                                    mem_start_q <= 1'b1;
                                    state_q <= ES_MEM_WAIT;
                                end
                            end
                            CMD_SET_MEM_BURST: begin
                                if (cmd_len_i != 8'd10) begin
                                    emit_no_payload(cmd_seq_i, ST_BAD_CMD);
                                end else if (!core_halted_i) begin
                                    emit_no_payload(cmd_seq_i, ST_NOT_HALTED);
                                end else if (cmd_payload_i[5] == 8'd0) begin
                                    emit_no_payload(cmd_seq_i, ST_BAD_CMD);
                                end else begin
                                    mem_addr_word = payload_word_be(cmd_payload_i[0], cmd_payload_i[1],
                                                                     cmd_payload_i[2], cmd_payload_i[3]);
                                    mem_size_field = cmd_payload_i[4][1:0];
                                    mem_data_word = payload_word_be(cmd_payload_i[6], cmd_payload_i[7],
                                                                     cmd_payload_i[8], cmd_payload_i[9]);
                                    mem_is_read_q <= 1'b0;
                                    mem_is_burst_q <= 1'b1;
                                    mem_burst_is_set_q <= 1'b1;
                                    mem_addr_q <= mem_addr_word;
                                    mem_wdata_q <= mem_data_word;
                                    mem_size_q <= (mem_size_field == 2'b00) ? SIZE_BYTE
                                               : (mem_size_field == 2'b01) ? SIZE_HALF
                                               : SIZE_WORD;
                                    mem_burst_count_q <= cmd_payload_i[5];
                                    mem_start_q <= 1'b1;
                                    state_q <= ES_MEM_WAIT;
                                end
                            end
                            default: emit_no_payload(cmd_seq_i, ST_BAD_CMD);
                        endcase
                    end
                end
                ES_GPR_READ_DELAY: begin
                    emit_word(cmd_seq_q, ST_OK, gpr_rdata_i);
                    state_q <= ES_IDLE;
                end
                ES_MEM_WAIT: begin
                    if (mem_done_valid) begin
                        resp_seq_o <= cmd_seq_q;
                        resp_status_o <= mem_done_status;
                        resp_len_o <= mem_done_len;
                        for (i = 0; i < 32; i = i + 1) begin
                            resp_payload_o[i] <= mem_done_payload[i];
                        end
                        resp_valid_o <= 1'b1;
                        state_q <= ES_IDLE;
                    end
                end
                default: begin
                    state_q <= ES_IDLE;
                end
            endcase
        end
    end
endmodule : debug_uart_agent_executor
