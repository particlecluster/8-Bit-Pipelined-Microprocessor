module InstructionMemory #(
    parameter integer ADDR_W  = 8,
    parameter integer INSTR_W = 16
) (
    input  wire [ADDR_W-1:0]  pc,
    output wire [INSTR_W-1:0] instr
);
    reg [INSTR_W-1:0] memory [0:(1<<ADDR_W)-1];
    assign instr = memory[pc];
endmodule
