`timescale 1ns / 1ps

module InstructionMemory (
    input  wire [7:0]  pc,
    output wire [15:0] instr
);
    reg [15:0] memory [0:255];

    initial begin
        $readmemh("program.hex", memory);
    end

    assign instr = memory[pc];
endmodule
