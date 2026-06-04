module imm_ext(

    input  [4:0] imm,

    output [7:0] imm_ext

);

assign imm_ext = {{3{imm[4]}}, imm};

endmodule
