`ifndef SYNCH_V
  `define SYNCH_V

  module synch#(
    parameter DATA_WIDTH = 32
  ) (
    input                       clk,
    input     [DATA_WIDTH-1:0]  i,
    output reg[DATA_WIDTH-1:0]  o
  );

    always@(posedge clk) begin
      o <= i;
    end

  endmodule

`endif
