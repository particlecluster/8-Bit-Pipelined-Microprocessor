`timescape 1ns / 1ps

module Extender (
    input  wire [4:0] imm5,
    output wire [7:0] imm5_sext,
    output wire [7:0] imm5_zext
);
    assign imm5_sext = {{3{imm5[4]}}, imm5};
    assign imm5_zext = {3'b000, imm5};
endmodule
