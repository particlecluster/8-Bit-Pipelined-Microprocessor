`timescale 1ns / 1ps
`include "defines.v"
module ControlUnit #(
    parameter integer OPCODE_W = 5
) (
    input  wire [OPCODE_W-1:0] opcode,
    input  wire                zero,
    input  wire                greater,
    output reg                 reg_we,
    output reg                 mem_we,
    output reg  [1:0]          alu_b_src,
    output reg  [1:0]          res_src,
    output reg                 pc_src,
    output reg                 rs1_src,
    output reg                 rs2_src,
    output reg                 mem_addr_src,
    output reg                 base_reg_src,
    output reg                 halt
);
    always @(*) begin
        reg_we       = 0;  mem_we       = 0;  pc_src       = 0;
        halt         = 0;  alu_b_src    = 2'b00; res_src   = 2'b00;
        mem_addr_src = 0;  base_reg_src = 0;  rs1_src      = 0;  rs2_src = 0;

        case(opcode)
            `OP_ADD, `OP_SUB, `OP_AND, `OP_OR, `OP_XOR, `OP_SHL, `OP_SHR, `OP_SLT,
            `OP_MUL, `OP_MAC, `OP_ROL, `OP_ROR: begin
                reg_we = 1;
            end
            `OP_LDI: begin 
                reg_we = 1;  res_src = 2'b10;
            end
            `OP_ADDI: begin 
                reg_we = 1;  alu_b_src = 2'b10;
            end
            `OP_LDD: begin 
                reg_we = 1;  res_src = 2'b01; base_reg_src = 0; mem_addr_src = 0;
            end
            `OP_STR: begin 
                mem_we = 1;  rs1_src = 1;     rs2_src = 1;      base_reg_src = 1; mem_addr_src = 0;
            end
            `OP_STD: begin 
                mem_we = 1;  rs1_src = 1;     mem_addr_src = 1;
            end
            `OP_JMP: begin
                pc_src = 1;
            end
            `OP_JZ, `OP_JNZ, `OP_JGT: begin
                alu_b_src = 2'b01; pc_src = 1; rs1_src = 1;
            end
            `OP_JAL: begin 
                reg_we = 1;  pc_src = 1; res_src = 2'b11; 
            end
            `OP_JR: begin 
                pc_src = 1;  rs1_src = 1; 
            end
            `OP_TRAP, `OP_ERET: begin
            end
            `OP_MFC0: begin
                reg_we = 1;
            end
            `OP_HALT: begin
                halt = 1;
            end
            default: ;
        endcase
    end
endmodule
