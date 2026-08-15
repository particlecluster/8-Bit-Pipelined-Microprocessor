`timescale 1ns / 1ps

module InstructionMemory #(
    parameter ADDR_W = 8,
    parameter INSTR_W = 16
) (
    input wire [ADDR_W-1:0] pc,
    output wire [INSTR_W-1:0] instr
);
    reg [INSTR_W-1:0] memory [0:(1<<ADDR_W)-1];
    integer i;

    initial begin
        for (i = 0; i < (1<<ADDR_W); i = i + 1)
            memory[i] = {INSTR_W{1'b0}};
        $readmemh("program.hex.txt", memory);
    end

    assign instr = memory[pc];
endmodule
