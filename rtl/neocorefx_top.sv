//
// neocorefx_top.sv
// NeoCoreFX - Minimal core wrapper
//

module neocorefx_top (
  // Clock/reset controls.
  input  logic       clk,
  input  logic       rst_n,

  // Counter enable.
  input  logic       en,

  // Demo status output.
  output logic [7:0] count
);
  counter #(
    .WIDTH(8)
  ) u_counter (
    .clk   (clk),
    .rst_n (rst_n),
    .en    (en),
    .count (count)
  );
endmodule : neocorefx_top
