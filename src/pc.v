`timescale 1ns / 1ps

module ProgramCounter (
    input  wire       clk,
    input  wire       rst,
    input  wire       halt,
    input  wire [7:0] next_pc,
    output reg  [7:0] pc
);
    always @(posedge clk) begin
        if (rst)       pc <= 8'b0000_0000;
        else if (halt) pc <= pc;
        else           pc <= next_pc;
    end
endmodule
