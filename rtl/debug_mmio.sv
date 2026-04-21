//
// debug_mmio.sv
// NeoCoreFX - Hardware debug MMIO register block
//

module debug_mmio (
    input  logic        clk,
    input  logic        rst,

    // Bus target request (NCX-style simple target)
    input  logic        req_i,
    input  logic        we_i,
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic [3:0]  sel_i,
    output logic        ack_o,
    output logic [31:0] rdata_o,
    output logic        err_o,

    // Core debug status/control
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

    output logic [3:0]  gpr_addr_o,
    input  logic [31:0] gpr_rdata_i,
    output logic        gpr_we_o,
    output logic [31:0] gpr_wdata_o,

    // Counters
    input  logic [31:0] cycle_count_i,
    input  logic [31:0] retire_count_i,
    input  logic [31:0] branch_redirect_count_i,
    input  logic [31:0] load_stall_count_i,
    input  logic [31:0] mem_stall_count_i,

    // Debug memory master (granted only when core halted by fabric policy)
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

    import mem_pkg::*;

    localparam logic [31:0] DBG_ID_VALUE = 32'h4E43_4442;      // "NCDB"
    localparam logic [31:0] DBG_CAPS_VALUE = 32'h0000_001F;    // halt/step/gpr/mem/counters
    localparam int unsigned DBG_MEM_TIMEOUT_CYCLES = 4096;

    localparam logic [1:0] SIZE_BYTE = 2'b00;
    localparam logic [1:0] SIZE_HALF = 2'b01;
    localparam logic [1:0] SIZE_WORD = 2'b10;

    logic req_prev_q;
    logic rsp_pending_q;
    logic rsp_err_q;
    logic [31:0] rsp_rdata_q;

    logic [3:0]  gpr_idx_q;
    logic [31:0] gpr_wdata_q;

    logic [31:0] mem_addr_q;
    logic [31:0] mem_wdata_q;
    logic [1:0]  mem_size_q;
    logic        mem_busy_q;
    logic [31:0] mem_rdata_q;
    logic        mem_done_sticky_q;
    logic        mem_err_sticky_q;
    logic        mem_timeout_sticky_q;
    logic [15:0] mem_timeout_ctr_q;

    logic [5:0]  reg_index_d;
    logic        req_valid_d;
    logic        req_new_d;

    logic        do_halt_req_d;
    logic        do_resume_req_d;
    logic        do_step_req_d;
    logic        do_gpr_we_d;

    logic [31:0] mem_status_word;

    function automatic logic [7:0] pick_lowest_sel_byte(
        input logic [31:0] data,
        input logic [3:0]  sel
    );
        begin
            if (sel[0]) return data[7:0];
            if (sel[1]) return data[15:8];
            if (sel[2]) return data[23:16];
            return data[31:24];
        end
    endfunction

    function automatic logic [1:0] decode_mem_size(input logic [1:0] size_field);
        case (size_field)
            2'b00: decode_mem_size = SIZE_BYTE;
            2'b01: decode_mem_size = SIZE_HALF;
            default: decode_mem_size = SIZE_WORD;
        endcase
    endfunction

    assign req_valid_d = req_i && debug_addr_in_range(addr_i);
    assign req_new_d = req_valid_d && !req_prev_q;
    assign reg_index_d = addr_i[7:2];

    assign mem_status_word = {
        16'h0000,
        mem_timeout_ctr_q,
        8'h00,
        core_halted_i,
        mem_timeout_sticky_q,
        mem_err_sticky_q,
        mem_done_sticky_q,
        mem_busy_q
    };

    assign halt_req_o = do_halt_req_d;
    assign resume_req_o = do_resume_req_d;
    assign step_req_o = do_step_req_d;

    assign gpr_addr_o = gpr_idx_q;
    assign gpr_wdata_o = gpr_wdata_q;
    assign gpr_we_o = do_gpr_we_d;

    assign dbg_mem_req_o = mem_busy_q;
    assign dbg_mem_size_o = mem_size_q;
    assign dbg_mem_addr_o = mem_addr_q;
    assign dbg_mem_wdata_o = mem_wdata_q;

    // Keep write direction explicit with a separate combinational alias.
    logic mem_we_q;
    assign dbg_mem_we_o = mem_we_q;

    always_ff @(posedge clk) begin
        logic [31:0] read_data;
        logic read_err;
        logic [7:0] cmd_byte;
        logic [7:0] gpr_cmd_byte;
        logic [7:0] mem_cmd_byte;
        logic [7:0] mem_status_w1c;

        do_halt_req_d = 1'b0;
        do_resume_req_d = 1'b0;
        do_step_req_d = 1'b0;
        do_gpr_we_d = 1'b0;

        if (rst) begin
            req_prev_q <= 1'b0;
            rsp_pending_q <= 1'b0;
            rsp_err_q <= 1'b0;
            rsp_rdata_q <= 32'h0000_0000;

            ack_o <= 1'b0;
            err_o <= 1'b0;
            rdata_o <= 32'h0000_0000;

            gpr_idx_q <= 4'h0;
            gpr_wdata_q <= 32'h0000_0000;

            mem_addr_q <= 32'h0000_0000;
            mem_wdata_q <= 32'h0000_0000;
            mem_size_q <= SIZE_WORD;
            mem_we_q <= 1'b0;
            mem_busy_q <= 1'b0;
            mem_rdata_q <= 32'h0000_0000;
            mem_done_sticky_q <= 1'b0;
            mem_err_sticky_q <= 1'b0;
            mem_timeout_sticky_q <= 1'b0;
            mem_timeout_ctr_q <= 16'h0000;
        end else begin
            ack_o <= 1'b0;
            err_o <= 1'b0;
            rdata_o <= 32'h0000_0000;

            req_prev_q <= req_valid_d;

            if (rsp_pending_q) begin
                ack_o <= 1'b1;
                err_o <= rsp_err_q;
                rdata_o <= rsp_rdata_q;
                rsp_pending_q <= 1'b0;
            end

            if (mem_busy_q) begin
                if (dbg_mem_done_i) begin
                    mem_busy_q <= 1'b0;
                    mem_done_sticky_q <= 1'b1;
                    mem_err_sticky_q <= dbg_mem_err_i;
                    mem_rdata_q <= dbg_mem_rdata_i;
                end else if (mem_timeout_ctr_q >= DBG_MEM_TIMEOUT_CYCLES[15:0]) begin
                    mem_busy_q <= 1'b0;
                    mem_done_sticky_q <= 1'b1;
                    mem_timeout_sticky_q <= 1'b1;
                    mem_err_sticky_q <= 1'b1;
                end else begin
                    mem_timeout_ctr_q <= mem_timeout_ctr_q + 16'd1;
                end
            end

            if (req_new_d) begin
                read_data = 32'h0000_0000;
                read_err = 1'b0;
                cmd_byte = pick_lowest_sel_byte(wdata_i, sel_i);
                gpr_cmd_byte = cmd_byte;
                mem_cmd_byte = cmd_byte;
                mem_status_w1c = cmd_byte;

                if (we_i) begin
                    case (reg_index_d)
                        DEBUG_CTRL_OFFSET[7:2]: begin
                            if (cmd_byte[0]) do_halt_req_d = 1'b1;
                            if (cmd_byte[1]) do_resume_req_d = 1'b1;
                            if (cmd_byte[2]) do_step_req_d = 1'b1;
                        end

                        DEBUG_GPR_IDX_OFFSET[7:2]: begin
                            gpr_idx_q <= wdata_i[3:0];
                        end

                        DEBUG_GPR_WDATA_OFFSET[7:2]: begin
                            gpr_wdata_q <= wdata_i;
                        end

                        DEBUG_GPR_CMD_OFFSET[7:2]: begin
                            if (gpr_cmd_byte[1]) begin
                                if (core_halted_i) begin
                                    do_gpr_we_d = 1'b1;
                                end else begin
                                    // Illegal in run mode: mark sticky mem-style error channel.
                                    mem_err_sticky_q <= 1'b1;
                                end
                            end
                        end

                        DEBUG_MEM_ADDR_OFFSET[7:2]: begin
                            mem_addr_q <= wdata_i;
                        end

                        DEBUG_MEM_WDATA_OFFSET[7:2]: begin
                            mem_wdata_q <= wdata_i;
                        end

                        DEBUG_MEM_CMD_OFFSET[7:2]: begin
                            if (!mem_busy_q && core_halted_i) begin
                                if (mem_cmd_byte[0] || mem_cmd_byte[1]) begin
                                    mem_we_q <= mem_cmd_byte[1];
                                    mem_size_q <= decode_mem_size(mem_cmd_byte[3:2]);
                                    mem_busy_q <= 1'b1;
                                    mem_done_sticky_q <= 1'b0;
                                    mem_err_sticky_q <= 1'b0;
                                    mem_timeout_sticky_q <= 1'b0;
                                    mem_timeout_ctr_q <= 16'h0000;
                                end
                            end else if (!core_halted_i) begin
                                mem_err_sticky_q <= 1'b1;
                            end
                        end

                        DEBUG_MEM_STATUS_OFFSET[7:2]: begin
                            if (mem_status_w1c[1]) mem_done_sticky_q <= 1'b0;
                            if (mem_status_w1c[2]) mem_err_sticky_q <= 1'b0;
                            if (mem_status_w1c[3]) mem_timeout_sticky_q <= 1'b0;
                        end

                        default: begin end
                    endcase
                end else begin
                    case (reg_index_d)
                        DEBUG_ID_OFFSET[7:2]:             read_data = DBG_ID_VALUE;
                        DEBUG_CAPS_OFFSET[7:2]:           read_data = DBG_CAPS_VALUE;
                        DEBUG_CTRL_OFFSET[7:2]:           read_data = 32'h0000_0000;
                        DEBUG_STATUS_OFFSET[7:2]:         read_data = {
                                                            24'h000000,
                                                            core_last_fault_i,
                                                            core_halt_reason_i,
                                                            3'b000,
                                                            core_halted_i
                                                          };
                        DEBUG_PC_OFFSET[7:2]:             read_data = core_pc_i;
                        DEBUG_CAUSE_OFFSET[7:2]:          read_data = {
                                                            24'h000000,
                                                            core_last_fault_i,
                                                            core_halt_reason_i,
                                                            4'h0
                                                          };
                        DEBUG_GPR_IDX_OFFSET[7:2]:        read_data = {28'h0, gpr_idx_q};
                        DEBUG_GPR_RDATA_OFFSET[7:2]:      read_data = gpr_rdata_i;
                        DEBUG_GPR_WDATA_OFFSET[7:2]:      read_data = gpr_wdata_q;
                        DEBUG_GPR_CMD_OFFSET[7:2]:        read_data = 32'h0000_0000;
                        DEBUG_MEM_ADDR_OFFSET[7:2]:       read_data = mem_addr_q;
                        DEBUG_MEM_WDATA_OFFSET[7:2]:      read_data = mem_wdata_q;
                        DEBUG_MEM_RDATA_OFFSET[7:2]:      read_data = mem_rdata_q;
                        DEBUG_MEM_CMD_OFFSET[7:2]:        read_data = {28'h0, mem_size_q, mem_we_q};
                        DEBUG_MEM_STATUS_OFFSET[7:2]:     read_data = mem_status_word;
                        DEBUG_CYCLE_COUNT_OFFSET[7:2]:    read_data = cycle_count_i;
                        DEBUG_RETIRE_COUNT_OFFSET[7:2]:   read_data = retire_count_i;
                        DEBUG_REDIRECT_COUNT_OFFSET[7:2]: read_data = branch_redirect_count_i;
                        DEBUG_LOAD_STALL_OFFSET[7:2]:     read_data = load_stall_count_i;
                        DEBUG_MEM_STALL_OFFSET[7:2]:      read_data = mem_stall_count_i;
                        default: begin
                            read_err = 1'b1;
                        end
                    endcase
                end

                rsp_pending_q <= 1'b1;
                rsp_err_q <= read_err;
                rsp_rdata_q <= read_data;
            end
        end
    end

    logic unused_fault_payload;
    assign unused_fault_payload = core_last_fault_addr_i[0] ^ core_last_illegal_inst_i[0];
endmodule : debug_mmio
