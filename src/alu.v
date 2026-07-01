`timescale 1ns / 1ps

module ALU (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [7:0] rd_val,
    input  wire [4:0] alu_control,
    output reg  [7:0] result,
    output wire       zero,
    output wire       greater
);
    wire [15:0] mul_prod = a * b;

    always @(*) begin
        case (alu_control)
            5'b0_0000,
            5'b0_1110: result = a + b;
            5'b0_0001: result = a - b;
            5'b0_0010: result = a & b;
            5'b0_0011: result = a | b;
            5'b0_0100: result = a ^ b;
            5'b0_0101: result = a << b[2:0];
            5'b0_0110: result = a >> b[2:0];
            5'b0_1111: result = ($signed(a) < $signed(b)) ? 8'b0000_0001 : 8'b0000_0000;
            5'b1_0000: result = mul_prod[7:0];
            5'b1_0001: result = rd_val + mul_prod[7:0];
            5'b1_0010: result = (a << b[2:0]) | (a >> (8 - b[2:0]));
            5'b1_0011: result = (a >> b[2:0]) | (a << (8 - b[2:0]));
            default:   result = 8'b0000_0000;
        endcase
    end

    assign zero    = (a == b);
    assign greater = ($signed(a) > $signed(b));
endmodule
