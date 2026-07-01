`timescale 1ns / 1ps

module RegisterFile (
    input  wire       clk,
    input  wire       we,
    input  wire [2:0] rs1,
    input  wire [2:0] rs2,
    input  wire [2:0] rd,
    input  wire [7:0] wd,
    output wire [7:0] rd1,
    output wire [7:0] rd2,
    output wire [7:0] rd3
);
    reg [7:0] registers [0:7];
    integer i;

    initial begin
        for (i = 0; i < 8; i = i + 1) begin
            registers[i] = 8'h00;
        end
    end

    assign rd1 = (rs1 == 3'b000) ? 8'h00 : registers[rs1];
    assign rd2 = (rs2 == 3'b000) ? 8'h00 : registers[rs2];
    assign rd3 = (rd  == 3'b000) ? 8'h00 : registers[rd];

    always @(posedge clk) begin
        if (we && (rd != 3'b000)) registers[rd] <= wd;
    end
endmodule
