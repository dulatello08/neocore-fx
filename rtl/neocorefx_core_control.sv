//
// neocorefx_core_control.sv
// NeoCoreFX - pipeline control policy and predictor/RAS updates
//

module neocorefx_core_control
  import core_pkg::*;
(
    input  logic        run_i,
    input  logic        dbg_gpr_we_i,
    input  logic        dbg_pc_set_req_i,
    input  logic [31:0] dbg_pc_set_i,

    input  logic        core_halted_i,
    input  logic        wb_valid_i,
    input  logic        mem_wait_stall_i,
    input  logic        load_use_stall_i,

    input  logic        redirect_valid_i,
    input  logic [31:0] redirect_pc_i,
    input  logic        mispredict_i,

    input  logic        idex_valid_i,
    input  logic        idex_illegal_i,
    input  logic [2:0]  idex_branch_type_i,
    input  logic [31:0] idex_pc_i,
    input  logic        idex_pred_taken_i,
    input  logic [3:0]  idex_rd_i,
    input  logic        idex_is_jal_i,
    input  logic        idex_is_jalr_i,
    input  logic [3:0]  idex_rs1_addr_i,
    input  logic [31:0] idex_imm_i,

    output logic        can_halt_boundary_o,
    output logic        core_hold_o,
    output logic        dbg_gpr_we_o,

    output logic        if1_stall_o,
    output logic        if2_stall_o,
    output logic        if2_flush_o,
    output logic        id_stall_o,
    output logic        id_flush_o,
    output logic        id_bubble_o,
    output logic        exe_stall_o,
    output logic        exe_flush_o,
    output logic        mem_stall_o,
    output logic        mem_flush_o,

    output logic        dbg_redirect_valid_o,
    output logic [31:0] dbg_redirect_pc_o,
    output logic        if1_redirect_valid_o,
    output logic [31:0] if1_redirect_pc_o,

    output logic        bp_update_valid_o,
    output logic [31:0] bp_update_pc_o,
    output logic        bp_update_taken_o,
    output logic        ras_push_valid_o,
    output logic [31:0] ras_push_addr_o,
    output logic        ras_pop_valid_o
);
    localparam logic [3:0] ABI_LR_REG = 4'hB;

    assign can_halt_boundary_o = wb_valid_i && !mem_wait_stall_i;
    assign dbg_redirect_valid_o = dbg_pc_set_req_i && core_halted_i;
    assign dbg_redirect_pc_o = {dbg_pc_set_i[31:2], 2'b00};
    assign if1_redirect_valid_o = redirect_valid_i || dbg_redirect_valid_o;
    assign if1_redirect_pc_o = redirect_valid_i ? redirect_pc_i : dbg_redirect_pc_o;

    assign core_hold_o = !run_i || core_halted_i;
    assign dbg_gpr_we_o = dbg_gpr_we_i && core_halted_i;

    assign if1_stall_o = core_hold_o || mem_wait_stall_i || load_use_stall_i;
    assign if2_stall_o = core_hold_o || mem_wait_stall_i || load_use_stall_i;
    assign if2_flush_o = mispredict_i;

    assign id_stall_o = core_hold_o || mem_wait_stall_i;
    assign id_flush_o = mispredict_i;
    assign id_bubble_o = load_use_stall_i && !core_hold_o && !mem_wait_stall_i;

    assign exe_stall_o = core_hold_o || mem_wait_stall_i;
    assign exe_flush_o = 1'b0;

    assign mem_stall_o = core_hold_o;
    assign mem_flush_o = 1'b0;

    assign bp_update_valid_o = idex_valid_i
                            && !exe_stall_o
                            && !idex_illegal_i
                            && ((idex_branch_type_i == BR_EQ)
                             || (idex_branch_type_i == BR_NE)
                             || (idex_branch_type_i == BR_LT)
                             || (idex_branch_type_i == BR_LTU));
    assign bp_update_pc_o = idex_pc_i;
    assign bp_update_taken_o = idex_pred_taken_i ^ mispredict_i;

    assign ras_push_valid_o = idex_valid_i
                           && !exe_stall_o
                           && !idex_illegal_i
                           && (idex_rd_i == ABI_LR_REG)
                           && (idex_is_jal_i || idex_is_jalr_i);
    assign ras_push_addr_o = idex_pc_i + 32'd4;

    assign ras_pop_valid_o = idex_valid_i
                          && !exe_stall_o
                          && !idex_illegal_i
                          && idex_is_jalr_i
                          && (idex_rd_i == 4'h0)
                          && (idex_rs1_addr_i == ABI_LR_REG)
                          && (idex_imm_i == 32'h0000_0000);
endmodule
