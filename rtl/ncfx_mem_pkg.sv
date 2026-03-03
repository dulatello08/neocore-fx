package ncfx_mem_pkg;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int unsigned NCFX_MEM_BYTES = 64 * 1024;
    localparam int unsigned NCFX_MEM_WORD_BYTES = 4;
    localparam int unsigned NCFX_MEM_WORDS = NCFX_MEM_BYTES / NCFX_MEM_WORD_BYTES;
    localparam logic [31:0] NCFX_MEM_BASE_ADDR = 32'h0000_0000;
    localparam logic [31:0] NCFX_MEM_LAST_ADDR = NCFX_MEM_BASE_ADDR + NCFX_MEM_BYTES - 1;

    function automatic logic ncfx_mem_addr_in_range(input logic [31:0] addr);
        return (addr >= NCFX_MEM_BASE_ADDR) && (addr <= NCFX_MEM_LAST_ADDR);
    endfunction

    function automatic logic [13:0] ncfx_mem_word_index(input logic [31:0] addr);
        return addr[15:2];
    endfunction

    function automatic logic [31:0] ncfx_mem_apply_write_sel(
        input logic [31:0] old_word,
        input logic [31:0] new_word,
        input logic [3:0]  sel
    );
        logic [31:0] merged;
        begin
            merged = old_word;
            if (sel[3]) merged[31:24] = new_word[31:24];
            if (sel[2]) merged[23:16] = new_word[23:16];
            if (sel[1]) merged[15:8]  = new_word[15:8];
            if (sel[0]) merged[7:0]   = new_word[7:0];
            return merged;
        end
    endfunction
endpackage
