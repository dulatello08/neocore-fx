//
// core_pkg.sv
// NeoCoreFX - Shared pipeline/control definitions
//

package core_pkg;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int unsigned GPR_COUNT = 16;

    typedef enum logic [4:0] {
        ALU_ADD    = 5'd0,
        ALU_SUB    = 5'd1,
        ALU_AND    = 5'd2,
        ALU_OR     = 5'd3,
        ALU_XOR    = 5'd4,
        ALU_SLT    = 5'd5,
        ALU_SLTU   = 5'd6,
        ALU_SLL    = 5'd7,
        ALU_SRL    = 5'd8,
        ALU_SRA    = 5'd9,
        ALU_MUL    = 5'd10,
        ALU_MULH   = 5'd11,
        ALU_MULHU  = 5'd12,
        ALU_MULHSU = 5'd13,
        ALU_PASS   = 5'd31
    } alu_op_t;

    typedef enum logic [2:0] {
        BR_NONE   = 3'd0,
        BR_UNCOND = 3'd1,
        BR_EQ     = 3'd2,
        BR_NE     = 3'd3,
        BR_LT     = 3'd4,
        BR_LTU    = 3'd5
    } branch_t;

    typedef enum logic [1:0] {
        SIZE_BYTE = 2'b00,
        SIZE_HALF = 2'b01,
        SIZE_WORD = 2'b10
    } mem_size_t;

    typedef enum logic [1:0] {
        FWD_NONE = 2'd0,
        FWD_MEM  = 2'd1,
        FWD_WB   = 2'd2
    } fwd_sel_t;

    function automatic logic [31:0] sext16(input logic [15:0] imm16);
        return {{16{imm16[15]}}, imm16};
    endfunction

    function automatic logic [31:0] zext16(input logic [15:0] imm16);
        return {16'h0000, imm16};
    endfunction

    function automatic logic [31:0] sext16_shift2(input logic [15:0] imm16);
        return {{14{imm16[15]}}, imm16, 2'b00};
    endfunction

    function automatic logic [31:0] sext20_shift2(input logic [19:0] imm20);
        return {{10{imm20[19]}}, imm20, 2'b00};
    endfunction
endpackage : core_pkg
