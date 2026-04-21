//
// mem_pkg.sv
// NeoCoreFX - Shared memory constants and helpers
//

package mem_pkg;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int unsigned MEM_BYTES      = 64 * 1024;
    localparam int unsigned MEM_WORD_BYTES = 4;
    localparam int unsigned MEM_WORDS      = MEM_BYTES / MEM_WORD_BYTES;
    localparam logic [31:0] MEM_BASE_ADDR  = 32'h0000_0000;
    localparam logic [31:0] MEM_LAST_ADDR  = MEM_BASE_ADDR + MEM_BYTES - 1;

    localparam logic [31:0] MMIO_BASE_ADDR = 32'h4000_0000;
    localparam int unsigned MMIO_BYTES     = 4 * 1024;
    localparam logic [31:0] MMIO_LAST_ADDR = MMIO_BASE_ADDR + MMIO_BYTES - 1;

    localparam logic [31:0] UART_BASE_ADDR = MMIO_BASE_ADDR;
    localparam int unsigned UART_BYTES     = 256;
    localparam logic [31:0] UART_LAST_ADDR = UART_BASE_ADDR + UART_BYTES - 1;

    localparam logic [31:0] DEBUG_BASE_ADDR = MMIO_BASE_ADDR + 32'h0000_0300;
    localparam int unsigned DEBUG_BYTES     = 256;
    localparam logic [31:0] DEBUG_LAST_ADDR = DEBUG_BASE_ADDR + DEBUG_BYTES - 1;

    localparam logic [7:0] UART_TXDATA_OFFSET  = 8'h00;
    localparam logic [7:0] UART_RXDATA_OFFSET  = 8'h04;
    localparam logic [7:0] UART_STATUS_OFFSET  = 8'h08;
    localparam logic [7:0] UART_CTRL_OFFSET    = 8'h0C;
    localparam logic [7:0] UART_BAUDDIV_OFFSET = 8'h10;

    localparam logic [7:0] DEBUG_ID_OFFSET            = 8'h00;
    localparam logic [7:0] DEBUG_CAPS_OFFSET          = 8'h04;
    localparam logic [7:0] DEBUG_CTRL_OFFSET          = 8'h08;
    localparam logic [7:0] DEBUG_STATUS_OFFSET        = 8'h0C;
    localparam logic [7:0] DEBUG_PC_OFFSET            = 8'h10;
    localparam logic [7:0] DEBUG_CAUSE_OFFSET         = 8'h14;
    localparam logic [7:0] DEBUG_GPR_IDX_OFFSET       = 8'h18;
    localparam logic [7:0] DEBUG_GPR_RDATA_OFFSET     = 8'h1C;
    localparam logic [7:0] DEBUG_GPR_WDATA_OFFSET     = 8'h20;
    localparam logic [7:0] DEBUG_GPR_CMD_OFFSET       = 8'h24;
    localparam logic [7:0] DEBUG_MEM_ADDR_OFFSET      = 8'h28;
    localparam logic [7:0] DEBUG_MEM_WDATA_OFFSET     = 8'h2C;
    localparam logic [7:0] DEBUG_MEM_RDATA_OFFSET     = 8'h30;
    localparam logic [7:0] DEBUG_MEM_CMD_OFFSET       = 8'h34;
    localparam logic [7:0] DEBUG_MEM_STATUS_OFFSET    = 8'h38;
    localparam logic [7:0] DEBUG_CYCLE_COUNT_OFFSET   = 8'h40;
    localparam logic [7:0] DEBUG_RETIRE_COUNT_OFFSET  = 8'h44;
    localparam logic [7:0] DEBUG_REDIRECT_COUNT_OFFSET= 8'h48;
    localparam logic [7:0] DEBUG_LOAD_STALL_OFFSET    = 8'h4C;
    localparam logic [7:0] DEBUG_MEM_STALL_OFFSET     = 8'h50;

    function automatic logic mem_addr_in_range(input logic [31:0] addr);
        return (addr >= MEM_BASE_ADDR) && (addr <= MEM_LAST_ADDR);
    endfunction

    function automatic logic mmio_addr_in_range(input logic [31:0] addr);
        return (addr >= MMIO_BASE_ADDR) && (addr <= MMIO_LAST_ADDR);
    endfunction

    function automatic logic uart_addr_in_range(input logic [31:0] addr);
        return (addr >= UART_BASE_ADDR) && (addr <= UART_LAST_ADDR);
    endfunction

    function automatic logic debug_addr_in_range(input logic [31:0] addr);
        return (addr >= DEBUG_BASE_ADDR) && (addr <= DEBUG_LAST_ADDR);
    endfunction

    function automatic logic [13:0] mem_word_index(input logic [31:0] addr);
        return addr[15:2];
    endfunction

    function automatic logic [31:0] mem_apply_write_sel(
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
endpackage : mem_pkg
