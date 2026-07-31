`timescale 1ns / 1ps

module RegisterFile #(
    parameter integer DATA_W     = 8,
    parameter integer REG_ADDR_W = 3
) (
    input  wire                  clk,
    input  wire                  we,
    input  wire [REG_ADDR_W-1:0] wa,
    input  wire [DATA_W-1:0]     wd,
    input  wire [REG_ADDR_W-1:0] rs1,
    input  wire [REG_ADDR_W-1:0] rs2,
    input  wire [REG_ADDR_W-1:0] rs3,
    output wire [DATA_W-1:0]     rd1,
    output wire [DATA_W-1:0]     rd2,
    output wire [DATA_W-1:0]     rd3
);
    reg [DATA_W-1:0] registers [0:(1<<REG_ADDR_W)-1];
    integer i;
    
    initial begin
        for (i = 0; i < (1<<REG_ADDR_W); i = i + 1) begin
            registers[i] = {DATA_W{1'b0}};
        end
    end

    assign rd1 = (rs1 == {REG_ADDR_W{1'b0}}) ? {DATA_W{1'b0}} : (we && (wa == rs1)) ? wd : registers[rs1];
    assign rd2 = (rs2 == {REG_ADDR_W{1'b0}}) ? {DATA_W{1'b0}} : (we && (wa == rs2)) ? wd : registers[rs2];
    assign rd3 = (rs3 == {REG_ADDR_W{1'b0}}) ? {DATA_W{1'b0}} : (we && (wa == rs3)) ? wd : registers[rs3];

    always @(posedge clk) begin
        if (we && (wa != {REG_ADDR_W{1'b0}})) registers[wa] <= wd;
    end
endmodule
