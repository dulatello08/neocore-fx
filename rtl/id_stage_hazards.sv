//
// id_stage_hazards.sv
// NeoCoreFX - ID hazard detection and forwarding selection
//

module id_stage_hazards
  import core_pkg::*;
(
    input  logic       illegal_i,
    input  logic       if2_valid_i,
    input  logic [3:0] rs1_i,
    input  logic [3:0] rs2_i,
    input  logic       rs1_used_i,
    input  logic       rs2_used_i,
    input  logic       mem_write_i,

    input  logic       exe_valid_i,
    input  logic [3:0] exe_rd_i,
    input  logic       exe_reg_write_i,
    input  logic       exe_mem_read_i,

    input  logic       mem_valid_i,
    input  logic [3:0] mem_rd_i,
    input  logic       mem_reg_write_i,

    output logic       load_use_stall_o,
    output fwd_sel_t   fwd_rs1_sel_o,
    output fwd_sel_t   fwd_rs2_sel_o
);
    always_comb begin
        load_use_stall_o = !illegal_i
                        && if2_valid_i
                        && exe_valid_i
                        && exe_mem_read_i
                        && (exe_rd_i != 4'h0)
                        && ((rs1_used_i && (exe_rd_i == rs1_i))
                         || (rs2_used_i && !mem_write_i && (exe_rd_i == rs2_i)));

        fwd_rs1_sel_o = FWD_NONE;
        if (!illegal_i && rs1_used_i && (rs1_i != 4'h0)) begin
            if (exe_valid_i && exe_reg_write_i && !exe_mem_read_i
             && (exe_rd_i == rs1_i) && (exe_rd_i != 4'h0)) begin
                fwd_rs1_sel_o = FWD_MEM;
            end else if (mem_valid_i && mem_reg_write_i
                      && (mem_rd_i == rs1_i) && (mem_rd_i != 4'h0)) begin
                fwd_rs1_sel_o = FWD_WB;
            end
        end

        fwd_rs2_sel_o = FWD_NONE;
        if (!illegal_i && rs2_used_i && (rs2_i != 4'h0)) begin
            if (exe_valid_i && exe_reg_write_i && !exe_mem_read_i
             && (exe_rd_i == rs2_i) && (exe_rd_i != 4'h0)) begin
                fwd_rs2_sel_o = FWD_MEM;
            end else if (mem_valid_i && mem_reg_write_i
                      && (mem_rd_i == rs2_i) && (mem_rd_i != 4'h0)) begin
                fwd_rs2_sel_o = FWD_WB;
            end
        end
    end
endmodule
