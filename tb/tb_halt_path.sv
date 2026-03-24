//
// tb_halt_path.sv
// Pipeline halt propagation testbench (B . -> halted)
//

`timescale 1ns/1ps

module tb_halt_path;
    import core_pkg::*;

    localparam int CLK_HALF_PERIOD_NS = 5;

    logic clk;
    logic rst;

    // ID control and IF2 inputs.
    logic        id_stall;
    logic        id_flush;
    logic        id_bubble;
    logic        if2_valid;
    logic [31:0] if2_pc;
    logic [31:0] if2_inst;
    logic        if2_pred_taken;
    logic [31:0] if2_pred_target;
    logic        if2_fetch_fault;

    // Register-file interface into ID.
    logic [3:0]  rf_rs1_addr;
    logic [3:0]  rf_rs2_addr;
    logic [31:0] rf_rs1_data;
    logic [31:0] rf_rs2_data;

    // Hazard/forward context into ID.
    logic        exe_valid_hz;
    logic [3:0]  exe_rd_hz;
    logic        exe_reg_write_hz;
    logic        exe_mem_read_hz;
    logic        mem_valid_hz;
    logic [3:0]  mem_rd_hz;
    logic        mem_reg_write_hz;
    logic        wb_valid_hz;
    logic [3:0]  wb_rd_hz;
    logic        wb_reg_write_hz;

    // ID -> EXE bundle.
    logic        idex_valid;
    logic [31:0] idex_pc;
    logic [3:0]  idex_rd;
    logic [3:0]  idex_rs1_addr;
    logic [3:0]  idex_rs2_addr;
    logic [31:0] idex_rs1_data;
    logic [31:0] idex_rs2_data;
    logic [31:0] idex_imm;
    logic [4:0]  idex_alu_op;
    logic        idex_alu_src_imm;
    logic        idex_mem_read;
    logic        idex_mem_write;
    logic [1:0]  idex_mem_size;
    logic        idex_load_sign_ext;
    logic        idex_reg_write;
    logic [2:0]  idex_branch_type;
    logic        idex_is_jal;
    logic        idex_is_jalr;
    logic        idex_is_lui;
    logic        idex_is_lpc;
    logic        idex_is_halt;
    logic        idex_pred_taken;
    logic [31:0] idex_pred_target;
    logic        idex_fetch_fault;
    logic [1:0]  idex_fwd_rs1_sel;
    logic [1:0]  idex_fwd_rs2_sel;
    logic        idex_illegal;

    logic load_use_stall;

    // EXE stage controls and outputs.
    logic        exe_stall;
    logic        exe_flush;
    logic [31:0] mem_fwd_data;
    logic [31:0] wb_fwd_data;
    logic        redirect_valid;
    logic [31:0] redirect_pc;
    logic        mispredict;

    logic        exe_mem_valid;
    logic [3:0]  exe_mem_rd;
    logic [3:0]  exe_mem_store_rs2_addr;
    logic        exe_mem_reg_write;
    logic        exe_mem_mem_read;
    logic        exe_mem_mem_write;
    logic [1:0]  exe_mem_mem_size;
    logic        exe_mem_load_sign_ext;
    logic [31:0] exe_mem_result;
    logic [31:0] exe_mem_store_data;
    logic        exe_mem_fetch_fault;
    logic        exe_mem_illegal;
    logic        exe_mem_is_halt;

    // MEM stage controls and outputs.
    logic        mem_stall;
    logic        mem_flush;
    logic        wb_fwd_valid;
    logic [3:0]  wb_fwd_rd;
    logic [31:0] wb_fwd_data_mem;
    logic        d_done;
    logic [31:0] d_rdata;
    logic        d_err;

    logic        d_req;
    logic        d_we;
    logic [1:0]  d_size;
    logic [31:0] d_addr;
    logic [31:0] d_wdata;
    logic        stall_req;

    logic        memwb_valid;
    logic [3:0]  memwb_rd;
    logic        memwb_reg_write;
    logic [31:0] memwb_data;
    logic        memwb_mem_fault;
    logic        memwb_fetch_fault;
    logic        memwb_illegal;
    logic        memwb_is_halt;

    // WB outputs.
    logic        rf_we;
    logic [3:0]  rf_waddr;
    logic [31:0] rf_wdata;
    logic        wb_valid;
    logic        wb_fault;
    logic        halted;

    int pass_count;
    int fail_count;

    id_stage u_id (
        .clk                (clk),
        .rst                (rst),
        .stall_i            (id_stall),
        .flush_i            (id_flush),
        .bubble_i           (id_bubble),
        .if2_valid_i        (if2_valid),
        .if2_pc_i           (if2_pc),
        .if2_inst_i         (if2_inst),
        .if2_pred_taken_i   (if2_pred_taken),
        .if2_pred_target_i  (if2_pred_target),
        .if2_fetch_fault_i  (if2_fetch_fault),
        .rf_rs1_addr_o      (rf_rs1_addr),
        .rf_rs2_addr_o      (rf_rs2_addr),
        .rf_rs1_data_i      (rf_rs1_data),
        .rf_rs2_data_i      (rf_rs2_data),
        .exe_valid_i        (exe_valid_hz),
        .exe_rd_i           (exe_rd_hz),
        .exe_reg_write_i    (exe_reg_write_hz),
        .exe_mem_read_i     (exe_mem_read_hz),
        .mem_valid_i        (mem_valid_hz),
        .mem_rd_i           (mem_rd_hz),
        .mem_reg_write_i    (mem_reg_write_hz),
        .wb_valid_i         (wb_valid_hz),
        .wb_rd_i            (wb_rd_hz),
        .wb_reg_write_i     (wb_reg_write_hz),
        .load_use_stall_o   (load_use_stall),
        .idex_valid_o       (idex_valid),
        .idex_pc_o          (idex_pc),
        .idex_rd_o          (idex_rd),
        .idex_rs1_addr_o    (idex_rs1_addr),
        .idex_rs2_addr_o    (idex_rs2_addr),
        .idex_rs1_data_o    (idex_rs1_data),
        .idex_rs2_data_o    (idex_rs2_data),
        .idex_imm_o         (idex_imm),
        .idex_alu_op_o      (idex_alu_op),
        .idex_alu_src_imm_o (idex_alu_src_imm),
        .idex_mem_read_o    (idex_mem_read),
        .idex_mem_write_o   (idex_mem_write),
        .idex_mem_size_o    (idex_mem_size),
        .idex_load_sign_ext_o(idex_load_sign_ext),
        .idex_reg_write_o   (idex_reg_write),
        .idex_branch_type_o (idex_branch_type),
        .idex_is_jal_o      (idex_is_jal),
        .idex_is_jalr_o     (idex_is_jalr),
        .idex_is_lui_o      (idex_is_lui),
        .idex_is_lpc_o      (idex_is_lpc),
        .idex_is_halt_o     (idex_is_halt),
        .idex_pred_taken_o  (idex_pred_taken),
        .idex_pred_target_o (idex_pred_target),
        .idex_fetch_fault_o (idex_fetch_fault),
        .idex_fwd_rs1_sel_o (idex_fwd_rs1_sel),
        .idex_fwd_rs2_sel_o (idex_fwd_rs2_sel),
        .idex_illegal_o     (idex_illegal)
    );

    exe_stage u_exe (
        .clk                (clk),
        .rst                (rst),
        .stall_i            (exe_stall),
        .flush_i            (exe_flush),
        .id_valid_i         (idex_valid),
        .id_pc_i            (idex_pc),
        .id_rd_i            (idex_rd),
        .id_rs1_addr_i      (idex_rs1_addr),
        .id_rs2_addr_i      (idex_rs2_addr),
        .id_rs1_data_i      (idex_rs1_data),
        .id_rs2_data_i      (idex_rs2_data),
        .id_imm_i           (idex_imm),
        .id_alu_op_i        (idex_alu_op),
        .id_alu_src_imm_i   (idex_alu_src_imm),
        .id_reg_write_i     (idex_reg_write),
        .id_mem_read_i      (idex_mem_read),
        .id_mem_write_i     (idex_mem_write),
        .id_mem_size_i      (idex_mem_size),
        .id_load_sign_ext_i (idex_load_sign_ext),
        .id_branch_type_i   (idex_branch_type),
        .id_is_jal_i        (idex_is_jal),
        .id_is_jalr_i       (idex_is_jalr),
        .id_is_lui_i        (idex_is_lui),
        .id_is_lpc_i        (idex_is_lpc),
        .id_is_halt_i       (idex_is_halt),
        .id_pred_taken_i    (idex_pred_taken),
        .id_pred_target_i   (idex_pred_target),
        .id_fetch_fault_i   (idex_fetch_fault),
        .id_illegal_i       (idex_illegal),
        .id_fwd_rs1_sel_i   (idex_fwd_rs1_sel),
        .id_fwd_rs2_sel_i   (idex_fwd_rs2_sel),
        .mem_fwd_data_i     (mem_fwd_data),
        .wb_fwd_data_i      (wb_fwd_data),
        .redirect_valid_o   (redirect_valid),
        .redirect_pc_o      (redirect_pc),
        .mispredict_o       (mispredict),
        .mem_valid_o        (exe_mem_valid),
        .mem_rd_o           (exe_mem_rd),
        .mem_store_rs2_addr_o(exe_mem_store_rs2_addr),
        .mem_reg_write_o    (exe_mem_reg_write),
        .mem_mem_read_o     (exe_mem_mem_read),
        .mem_mem_write_o    (exe_mem_mem_write),
        .mem_mem_size_o     (exe_mem_mem_size),
        .mem_load_sign_ext_o(exe_mem_load_sign_ext),
        .mem_result_o       (exe_mem_result),
        .mem_store_data_o   (exe_mem_store_data),
        .mem_fetch_fault_o  (exe_mem_fetch_fault),
        .mem_illegal_o      (exe_mem_illegal),
        .mem_is_halt_o      (exe_mem_is_halt)
    );

    mem_stage u_mem (
        .clk                (clk),
        .rst                (rst),
        .stall_i            (mem_stall),
        .flush_i            (mem_flush),
        .exe_valid_i        (exe_mem_valid),
        .exe_rd_i           (exe_mem_rd),
        .exe_store_rs2_addr_i(exe_mem_store_rs2_addr),
        .exe_reg_write_i    (exe_mem_reg_write),
        .exe_mem_read_i     (exe_mem_mem_read),
        .exe_mem_write_i    (exe_mem_mem_write),
        .exe_mem_size_i     (exe_mem_mem_size),
        .exe_load_sign_ext_i(exe_mem_load_sign_ext),
        .exe_result_i       (exe_mem_result),
        .exe_store_data_i   (exe_mem_store_data),
        .exe_fetch_fault_i  (exe_mem_fetch_fault),
        .exe_illegal_i      (exe_mem_illegal),
        .exe_is_halt_i      (exe_mem_is_halt),
        .wb_fwd_valid_i     (wb_fwd_valid),
        .wb_fwd_rd_i        (wb_fwd_rd),
        .wb_fwd_data_i      (wb_fwd_data_mem),
        .d_done_i           (d_done),
        .d_rdata_i          (d_rdata),
        .d_err_i            (d_err),
        .d_req_o            (d_req),
        .d_we_o             (d_we),
        .d_size_o           (d_size),
        .d_addr_o           (d_addr),
        .d_wdata_o          (d_wdata),
        .stall_req_o        (stall_req),
        .memwb_valid_o      (memwb_valid),
        .memwb_rd_o         (memwb_rd),
        .memwb_reg_write_o  (memwb_reg_write),
        .memwb_data_o       (memwb_data),
        .memwb_mem_fault_o  (memwb_mem_fault),
        .memwb_fetch_fault_o(memwb_fetch_fault),
        .memwb_illegal_o    (memwb_illegal),
        .memwb_is_halt_o    (memwb_is_halt)
    );

    wb_stage u_wb (
        .memwb_valid_i      (memwb_valid),
        .memwb_rd_i         (memwb_rd),
        .memwb_reg_write_i  (memwb_reg_write),
        .memwb_data_i       (memwb_data),
        .memwb_mem_fault_i  (memwb_mem_fault),
        .memwb_fetch_fault_i(memwb_fetch_fault),
        .memwb_illegal_i    (memwb_illegal),
        .memwb_is_halt_i    (memwb_is_halt),
        .rf_we_o            (rf_we),
        .rf_waddr_o         (rf_waddr),
        .rf_wdata_o         (rf_wdata),
        .wb_valid_o         (wb_valid),
        .wb_fault_o         (wb_fault),
        .halted_o           (halted)
    );

    always begin
        #(CLK_HALF_PERIOD_NS) clk = ~clk;
    end

    task automatic check_true(input bit cond, input string msg);
        if (!cond) begin
            fail_count = fail_count + 1;
            $error("FAIL: %s", msg);
        end else begin
            pass_count = pass_count + 1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;

        id_stall = 1'b0;
        id_flush = 1'b0;
        id_bubble = 1'b0;
        if2_valid = 1'b0;
        if2_pc = 32'h0000_1000;
        if2_inst = 32'h0000_0000;
        if2_pred_taken = 1'b0;
        if2_pred_target = 32'h0000_0000;
        if2_fetch_fault = 1'b0;

        rf_rs1_data = 32'h0000_0000;
        rf_rs2_data = 32'h0000_0000;

        exe_valid_hz = 1'b0;
        exe_rd_hz = 4'h0;
        exe_reg_write_hz = 1'b0;
        exe_mem_read_hz = 1'b0;
        mem_valid_hz = 1'b0;
        mem_rd_hz = 4'h0;
        mem_reg_write_hz = 1'b0;
        wb_valid_hz = 1'b0;
        wb_rd_hz = 4'h0;
        wb_reg_write_hz = 1'b0;

        exe_stall = 1'b0;
        exe_flush = 1'b0;
        mem_fwd_data = 32'h0000_0000;
        wb_fwd_data = 32'h0000_0000;

        mem_stall = 1'b0;
        mem_flush = 1'b0;
        wb_fwd_valid = 1'b0;
        wb_fwd_rd = 4'h0;
        wb_fwd_data_mem = 32'h0000_0000;
        d_done = 1'b1;
        d_rdata = 32'h0000_0000;
        d_err = 1'b0;

        pass_count = 0;
        fail_count = 0;

        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_halt_path.vcd");
            $dumpvars(0, tb_halt_path);
        end

        repeat (4) @(posedge clk);
        rst <= 1'b0;

        // B . encoding (BR class, op=0, offset=0) should decode as halt.
        if2_valid <= 1'b1;
        if2_pred_taken <= 1'b1;
        if2_pred_target <= 32'h0000_1000;
        if2_pc <= 32'h0000_1000;
        if2_inst <= 32'h4000_0000;

        @(posedge clk);
        #1;
        check_true(idex_valid, "ID produces valid pipeline entry for B .");
        check_true(idex_is_halt, "ID marks B . as halt");
        check_true(idex_branch_type == BR_UNCOND, "B . remains unconditional branch type");

        // Stop injecting instructions.
        if2_valid <= 1'b0;
        if2_pred_taken <= 1'b0;
        if2_pred_target <= 32'h0000_0000;
        if2_inst <= 32'h0000_0000;

        @(posedge clk);
        #1;
        check_true(exe_mem_valid, "EXE propagates valid entry");
        check_true(exe_mem_is_halt, "EXE propagates halt bit");
        check_true(!redirect_valid && !mispredict, "Halt path does not create redirect or mispredict");

        @(posedge clk);
        #1;
        check_true(memwb_valid, "MEM propagates valid entry");
        check_true(memwb_is_halt, "MEM/WB carries halt bit");
        check_true(halted, "WB raises halted signal when halt retires");
        check_true(!rf_we, "Halt does not trigger register writeback");

        $display("PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count != 0) begin
            $fatal(1, "tb_halt_path failed");
        end
        $finish;
    end
endmodule
