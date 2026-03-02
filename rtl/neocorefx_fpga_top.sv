module neocorefx_fpga_top (
    input  logic       clk_25mhz,
    input  logic [6:0] btn,
    output logic [7:0] led
);
    logic [7:0] count;

    neocorefx_top u_core (
        .clk   (clk_25mhz),
        .rst_n (btn[0]),
        .en    (1'b1),
        .count (count)
    );

    always_comb begin
        led = count;
    end
endmodule
