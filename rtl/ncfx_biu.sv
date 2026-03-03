module ncfx_biu (
    input  logic        clk,
    input  logic        rst_n,

    // CPU I-Port: 32-bit read-only fetch
    input  logic        i_req,
    input  logic [31:0] i_addr,
    output logic        i_busy,
    output logic        i_done,
    output logic [31:0] i_rdata,
    output logic        i_err,

    // CPU D-Port: 8/16/32-bit read/write
    input  logic        d_req,
    input  logic        d_we,
    input  logic [1:0]  d_size,
    input  logic [31:0] d_addr,
    input  logic [31:0] d_wdata,
    output logic        d_busy,
    output logic        d_done,
    output logic [31:0] d_rdata,
    output logic        d_err,

    // I-Bus (NCX)
    output logic        ibus_cyc,
    output logic        ibus_stb,
    output logic [31:0] ibus_addr,
    input  logic        ibus_ack,
    input  logic [31:0] ibus_rdata,
    input  logic        ibus_err,

    // D-Bus (NCX)
    output logic        dbus_cyc,
    output logic        dbus_stb,
    output logic        dbus_we,
    output logic [31:0] dbus_addr,
    output logic [31:0] dbus_wdata,
    output logic [3:0]  dbus_sel,
    input  logic        dbus_ack,
    input  logic [31:0] dbus_rdata,
    input  logic        dbus_err
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam logic [1:0] NCFX_SIZE_BYTE = 2'b00;
    localparam logic [1:0] NCFX_SIZE_HALF = 2'b01;
    localparam logic [1:0] NCFX_SIZE_WORD = 2'b10;

    logic [1:0] d_size_q;
    logic [1:0] d_addr_lsb_q;
    logic       d_we_q;

    function automatic logic d_size_valid(input logic [1:0] size);
        return (size == NCFX_SIZE_BYTE) || (size == NCFX_SIZE_HALF) || (size == NCFX_SIZE_WORD);
    endfunction

    function automatic logic d_is_aligned(input logic [1:0] size, input logic [1:0] lsb);
        case (size)
            NCFX_SIZE_BYTE: return 1'b1;
            NCFX_SIZE_HALF: return (lsb[0] == 1'b0);
            NCFX_SIZE_WORD: return (lsb == 2'b00);
            default:        return 1'b0;
        endcase
    endfunction

    function automatic logic [3:0] d_gen_sel(input logic [1:0] size, input logic [1:0] lsb);
        case (size)
            NCFX_SIZE_BYTE: begin
                case (lsb)
                    2'b00: return 4'b1000;
                    2'b01: return 4'b0100;
                    2'b10: return 4'b0010;
                    default: return 4'b0001;
                endcase
            end
            NCFX_SIZE_HALF: begin
                case (lsb)
                    2'b00: return 4'b1100;
                    2'b10: return 4'b0011;
                    default: return 4'b0000;
                endcase
            end
            NCFX_SIZE_WORD: return 4'b1111;
            default:        return 4'b0000;
        endcase
    endfunction

    function automatic logic [31:0] d_gen_wdata(
        input logic [1:0]  size,
        input logic [1:0]  lsb,
        input logic [31:0] data
    );
        case (size)
            NCFX_SIZE_BYTE: begin
                case (lsb)
                    2'b00: return {data[7:0], 24'h000000};
                    2'b01: return {8'h00, data[7:0], 16'h0000};
                    2'b10: return {16'h0000, data[7:0], 8'h00};
                    default: return {24'h000000, data[7:0]};
                endcase
            end
            NCFX_SIZE_HALF: begin
                case (lsb)
                    2'b00: return {data[15:0], 16'h0000};
                    2'b10: return {16'h0000, data[15:0]};
                    default: return 32'h0000_0000;
                endcase
            end
            NCFX_SIZE_WORD: return data;
            default:        return 32'h0000_0000;
        endcase
    endfunction

    function automatic logic [31:0] d_extract_rdata(
        input logic [31:0] word_data,
        input logic [1:0]  size,
        input logic [1:0]  lsb
    );
        case (size)
            NCFX_SIZE_BYTE: begin
                case (lsb)
                    2'b00: return {24'h000000, word_data[31:24]};
                    2'b01: return {24'h000000, word_data[23:16]};
                    2'b10: return {24'h000000, word_data[15:8]};
                    default: return {24'h000000, word_data[7:0]};
                endcase
            end
            NCFX_SIZE_HALF: begin
                case (lsb)
                    2'b00: return {16'h0000, word_data[31:16]};
                    2'b10: return {16'h0000, word_data[15:0]};
                    default: return 32'h0000_0000;
                endcase
            end
            NCFX_SIZE_WORD: return word_data;
            default:        return 32'h0000_0000;
        endcase
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_busy   <= 1'b0;
            i_done   <= 1'b0;
            i_rdata  <= 32'h0000_0000;
            i_err    <= 1'b0;
            ibus_cyc <= 1'b0;
            ibus_stb <= 1'b0;
            ibus_addr <= 32'h0000_0000;
        end else begin
            i_done <= 1'b0;
            i_err  <= 1'b0;

            if (!i_busy) begin
                if (i_req) begin
                    if (i_addr[1:0] != 2'b00) begin
                        i_done <= 1'b1;
                        i_err  <= 1'b1;
                    end else begin
                        i_busy    <= 1'b1;
                        ibus_cyc  <= 1'b1;
                        ibus_stb  <= 1'b1;
                        ibus_addr <= i_addr;
                    end
                end
            end else begin
                if (ibus_ack || ibus_err) begin
                    i_busy   <= 1'b0;
                    i_done   <= 1'b1;
                    i_err    <= ibus_err;
                    i_rdata  <= ibus_rdata;
                    ibus_cyc <= 1'b0;
                    ibus_stb <= 1'b0;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d_busy    <= 1'b0;
            d_done    <= 1'b0;
            d_rdata   <= 32'h0000_0000;
            d_err     <= 1'b0;
            d_size_q  <= NCFX_SIZE_WORD;
            d_addr_lsb_q <= 2'b00;
            d_we_q    <= 1'b0;
            dbus_cyc  <= 1'b0;
            dbus_stb  <= 1'b0;
            dbus_we   <= 1'b0;
            dbus_addr <= 32'h0000_0000;
            dbus_wdata <= 32'h0000_0000;
            dbus_sel  <= 4'b0000;
        end else begin
            d_done <= 1'b0;
            d_err  <= 1'b0;

            if (!d_busy) begin
                if (d_req) begin
                    if (!d_size_valid(d_size) || !d_is_aligned(d_size, d_addr[1:0])) begin
                        d_done <= 1'b1;
                        d_err  <= 1'b1;
                    end else begin
                        d_busy       <= 1'b1;
                        d_size_q     <= d_size;
                        d_addr_lsb_q <= d_addr[1:0];
                        d_we_q       <= d_we;
                        dbus_cyc     <= 1'b1;
                        dbus_stb     <= 1'b1;
                        dbus_we      <= d_we;
                        dbus_addr    <= d_addr;
                        dbus_sel     <= d_gen_sel(d_size, d_addr[1:0]);
                        dbus_wdata   <= d_gen_wdata(d_size, d_addr[1:0], d_wdata);
                    end
                end
            end else begin
                if (dbus_ack || dbus_err) begin
                    d_busy    <= 1'b0;
                    d_done    <= 1'b1;
                    d_err     <= dbus_err;
                    dbus_cyc  <= 1'b0;
                    dbus_stb  <= 1'b0;
                    dbus_we   <= 1'b0;

                    if (dbus_ack && !d_we_q) begin
                        d_rdata <= d_extract_rdata(dbus_rdata, d_size_q, d_addr_lsb_q);
                    end
                end
            end
        end
    end
endmodule
