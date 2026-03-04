//
// ncfx_core_pkg.sv
// NeoCoreFX - Shared pipeline/control definitions
//

package ncfx_core_pkg;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int unsigned NCFX_GPR_COUNT = 16;

    typedef enum logic [4:0] {
        NCFX_ALU_ADD    = 5'd0,
        NCFX_ALU_SUB    = 5'd1,
        NCFX_ALU_AND    = 5'd2,
        NCFX_ALU_OR     = 5'd3,
        NCFX_ALU_XOR    = 5'd4,
        NCFX_ALU_SLT    = 5'd5,
        NCFX_ALU_SLTU   = 5'd6,
        NCFX_ALU_SLL    = 5'd7,
        NCFX_ALU_SRL    = 5'd8,
        NCFX_ALU_SRA    = 5'd9,
        NCFX_ALU_MUL    = 5'd10,
        NCFX_ALU_MULH   = 5'd11,
        NCFX_ALU_MULHU  = 5'd12,
        NCFX_ALU_MULHSU = 5'd13,
        NCFX_ALU_PASS   = 5'd31
    } ncfx_alu_op_t;

    typedef enum logic [2:0] {
        NCFX_BR_NONE   = 3'd0,
        NCFX_BR_UNCOND = 3'd1,
        NCFX_BR_EQ     = 3'd2,
        NCFX_BR_NE     = 3'd3,
        NCFX_BR_LT     = 3'd4,
        NCFX_BR_LTU    = 3'd5
    } ncfx_branch_t;

    typedef enum logic [1:0] {
        NCFX_SIZE_BYTE = 2'b00,
        NCFX_SIZE_HALF = 2'b01,
        NCFX_SIZE_WORD = 2'b10
    } ncfx_mem_size_t;

    typedef enum logic [1:0] {
        NCFX_FWD_NONE = 2'd0,
        NCFX_FWD_MEM  = 2'd1,
        NCFX_FWD_WB   = 2'd2
    } ncfx_fwd_sel_t;

    function automatic logic [31:0] ncfx_sext16(input logic [15:0] imm16);
        return {{16{imm16[15]}}, imm16};
    endfunction

    function automatic logic [31:0] ncfx_zext16(input logic [15:0] imm16);
        return {16'h0000, imm16};
    endfunction

    function automatic logic [31:0] ncfx_sext16_shift2(input logic [15:0] imm16);
        return {{14{imm16[15]}}, imm16, 2'b00};
    endfunction

    function automatic logic [31:0] ncfx_sext20_shift2(input logic [19:0] imm20);
        return {{10{imm20[19]}}, imm20, 2'b00};
    endfunction
endpackage
