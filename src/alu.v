`timescale 1ns / 1ps

module ALU #(
    parameter integer DATA_W   = 8,
    parameter integer OPCODE_W = 5
) (
    input  wire [DATA_W-1:0]   a,
    input  wire [DATA_W-1:0]   b,
    input  wire [DATA_W-1:0]   rd_val,
    input  wire [OPCODE_W-1:0] alu_control,
    output reg  [DATA_W-1:0]   result,
    output wire                zero,
    output wire                greater
);
    wire [2*DATA_W-1:0] mul_prod = a * b;

    always @(*) begin
        case (alu_control)
            `OP_ADD, `OP_ADDI: result = a + b;
            `OP_SUB:           result = a - b;
            `OP_AND:           result = a & b;
            `OP_OR:            result = a | b;
            `OP_XOR:           result = a ^ b;
            `OP_SHL:           result = a << b[2:0];
            `OP_SHR:           result = a >> b[2:0];
            `OP_SLT:           result = ($signed(a) < $signed(b)) ? {{(DATA_W-1){1'b0}}, 1'b1} : {DATA_W{1'b0}};
            `OP_MUL:           result = mul_prod[DATA_W-1:0];
            `OP_MAC:           result = rd_val + mul_prod[DATA_W-1:0];
            `OP_ROL:           result = (a << b[2:0]) | (a >> (DATA_W - b[2:0]));
            `OP_ROR:           result = (a >> b[2:0]) | (a << (DATA_W - b[2:0]));
            default:           result = {DATA_W{1'b0}};
        endcase
    end

    assign zero    = (a == b);
    assign greater = ($signed(a) > $signed(b));
endmodule
