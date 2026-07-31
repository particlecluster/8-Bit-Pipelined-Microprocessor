`timescape 1ns / 1ps

module Extender #(
    parameter integer DATA_W = 8,
    parameter integer IMM5_W = 5
) (
    input  wire [IMM5_W-1:0] imm5,
    output wire [DATA_W-1:0] imm5_sext,
    output wire [DATA_W-1:0] imm5_zext
);
    assign imm5_sext = {{(DATA_W-IMM5_W){imm5[IMM5_W-1]}}, imm5};
    assign imm5_zext = {{(DATA_W-IMM5_W){1'b0}}, imm5};
endmodule
