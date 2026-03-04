//
// counter.sv
// NeoCoreFX - Simple synchronous up-counter
//

module counter #(
  parameter int unsigned WIDTH = 8
) (
  // Clock/reset controls.
  input  logic             clk,
  input  logic             rst_n,

  // Count enable.
  input  logic             en,

  // Counter value output.
  output logic [WIDTH-1:0] count
);
  timeunit 1ns;
  timeprecision 1ps;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= '0;
    end else if (en) begin
      count <= count + 1'b1;
    end
  end
endmodule : counter
