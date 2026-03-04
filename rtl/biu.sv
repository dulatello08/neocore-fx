//
// biu.sv
// NeoCoreFX - Bus Interface Unit (combinational bridge)
//

module biu (
    input  logic        clk,
    input  logic        rst,

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

    localparam logic [1:0] SIZE_BYTE = 2'b00;
    localparam logic [1:0] SIZE_HALF = 2'b01;
    localparam logic [1:0] SIZE_WORD = 2'b10;

    logic i_aligned;
    logic i_req_valid;
    logic i_rsp_done;

    logic d_size_ok;
    logic d_aligned;
    logic d_req_valid;
    logic d_rsp_done;

    function automatic logic d_size_valid(input logic [1:0] size);
        return (size == SIZE_BYTE) || (size == SIZE_HALF) || (size == SIZE_WORD);
    endfunction

    function automatic logic d_is_aligned(input logic [1:0] size, input logic [1:0] lsb);
        case (size)
            SIZE_BYTE: return 1'b1;
            SIZE_HALF: return (lsb[0] == 1'b0);
            SIZE_WORD: return (lsb == 2'b00);
            default:        return 1'b0;
        endcase
    endfunction

    function automatic logic [3:0] d_gen_sel(input logic [1:0] size, input logic [1:0] lsb);
        case (size)
            SIZE_BYTE: begin
                case (lsb)
                    2'b00: return 4'b1000;
                    2'b01: return 4'b0100;
                    2'b10: return 4'b0010;
                    default: return 4'b0001;
                endcase
            end
            SIZE_HALF: begin
                case (lsb)
                    2'b00: return 4'b1100;
                    2'b10: return 4'b0011;
                    default: return 4'b0000;
                endcase
            end
            SIZE_WORD: return 4'b1111;
            default:        return 4'b0000;
        endcase
    endfunction

    function automatic logic [31:0] d_gen_wdata(
        input logic [1:0]  size,
        input logic [1:0]  lsb,
        input logic [31:0] data
    );
        case (size)
            SIZE_BYTE: begin
                case (lsb)
                    2'b00: return {data[7:0], 24'h000000};
                    2'b01: return {8'h00, data[7:0], 16'h0000};
                    2'b10: return {16'h0000, data[7:0], 8'h00};
                    default: return {24'h000000, data[7:0]};
                endcase
            end
            SIZE_HALF: begin
                case (lsb)
                    2'b00: return {data[15:0], 16'h0000};
                    2'b10: return {16'h0000, data[15:0]};
                    default: return 32'h0000_0000;
                endcase
            end
            SIZE_WORD: return data;
            default:        return 32'h0000_0000;
        endcase
    endfunction

    function automatic logic [31:0] d_extract_rdata(
        input logic [31:0] word_data,
        input logic [1:0]  size,
        input logic [1:0]  lsb
    );
        case (size)
            SIZE_BYTE: begin
                case (lsb)
                    2'b00: return {24'h000000, word_data[31:24]};
                    2'b01: return {24'h000000, word_data[23:16]};
                    2'b10: return {24'h000000, word_data[15:8]};
                    default: return {24'h000000, word_data[7:0]};
                endcase
            end
            SIZE_HALF: begin
                case (lsb)
                    2'b00: return {16'h0000, word_data[31:16]};
                    2'b10: return {16'h0000, word_data[15:0]};
                    default: return 32'h0000_0000;
                endcase
            end
            SIZE_WORD: return word_data;
            default:        return 32'h0000_0000;
        endcase
    endfunction

    assign i_aligned = (i_addr[1:0] == 2'b00);
    assign i_req_valid = i_req && i_aligned;
    assign i_rsp_done = ibus_ack || ibus_err;

    assign d_size_ok = d_size_valid(d_size);
    assign d_aligned = d_is_aligned(d_size, d_addr[1:0]);
    assign d_req_valid = d_req && d_size_ok && d_aligned;
    assign d_rsp_done = dbus_ack || dbus_err;

    assign ibus_cyc = i_req_valid;
    assign ibus_stb = i_req_valid;
    assign ibus_addr = i_addr;

    assign i_busy = i_req_valid && !i_rsp_done;
    assign i_done = i_req && (!i_aligned || i_rsp_done);
    assign i_err = i_req && (!i_aligned || (i_req_valid && ibus_err));
    assign i_rdata = ibus_rdata;

    assign dbus_cyc = d_req_valid;
    assign dbus_stb = d_req_valid;
    assign dbus_we = d_req_valid && d_we;
    assign dbus_addr = d_addr;
    assign dbus_wdata = d_gen_wdata(d_size, d_addr[1:0], d_wdata);
    assign dbus_sel = d_req_valid ? d_gen_sel(d_size, d_addr[1:0]) : 4'b0000;

    assign d_busy = d_req_valid && !d_rsp_done;
    assign d_done = d_req && (!d_size_ok || !d_aligned || d_rsp_done);
    assign d_err = d_req && ((!d_size_ok || !d_aligned) || (d_req_valid && dbus_err));
    assign d_rdata = d_extract_rdata(dbus_rdata, d_size, d_addr[1:0]);

    logic unused_clk_rst;
    assign unused_clk_rst = clk ^ rst;
endmodule
