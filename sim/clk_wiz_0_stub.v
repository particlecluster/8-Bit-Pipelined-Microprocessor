// Clock Wizard Simulation Stub for Icarus Verilog simulation
`timescale 1ns / 1ps

module clk_wiz_0 (
    input  wire clk_in1,
    output reg  clk_out1
);
    reg [1:0] counter = 0;
    initial clk_out1 = 0;
    always @(posedge clk_in1) begin
        counter <= counter + 1'b1;
        if (counter == 2'd1) begin
            clk_out1 <= ~clk_out1;
            counter <= 0;
        end
    end
endmodule
