`timescale 1ns / 1ps

module ProgramCounter #(
    parameter integer ADDR_W = 8
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               halt,
    input  wire [ADDR_W-1:0]  next_pc,
    output reg  [ADDR_W-1:0]  pc
);
    always @(posedge clk) begin
        if (rst)       pc <= {ADDR_W{1'b0}};
        else if (halt) pc <= pc;
        else           pc <= next_pc;
    end
endmodule
