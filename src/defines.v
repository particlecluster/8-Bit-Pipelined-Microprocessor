`ifndef DEFINES_V
`define DEFINES_V

`define OP_ADD   5'b00000
`define OP_SUB   5'b00001
`define OP_AND   5'b00010
`define OP_OR    5'b00011
`define OP_XOR   5'b00100
`define OP_SHL   5'b00101
`define OP_SHR   5'b00110
`define OP_LDI   5'b00111
`define OP_LDD   5'b01000
`define OP_STR   5'b01001
`define OP_JMP   5'b01010
`define OP_JZ    5'b01011
`define OP_JNZ   5'b01100
`define OP_JGT   5'b01101
`define OP_ADDI  5'b01110
`define OP_SLT   5'b01111
`define OP_MUL   5'b10000
`define OP_MAC   5'b10001
`define OP_ROL   5'b10010
`define OP_ROR   5'b10011
`define OP_RETI  5'b10100
`define OP_STD   5'b10101
`define OP_JAL   5'b10110   
`define OP_JR    5'b10111   
`define OP_TRAP  5'b11000   
`define OP_ERET  5'b11001   
`define OP_MFC0  5'b11010   
`define OP_HALT  5'b11111

`endif
