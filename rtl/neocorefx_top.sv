module neocorefx_top (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       en,
    output logic [7:0] count
);
    ncfx_counter #(
        .WIDTH(8)
    ) u_counter (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .count (count)
    );
endmodule
