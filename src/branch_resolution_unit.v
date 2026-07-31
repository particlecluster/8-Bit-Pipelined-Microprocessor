`timescale 1ns / 1ps

module BranchResolutionUnit #(
    parameter integer ADDR_W   = 8,
    parameter integer OPCODE_W = 5
) (
    input  wire [ADDR_W-1:0]   ex_pc,
    input  wire [OPCODE_W-1:0] opcode,
    input  wire                pc_src,
    input  wire                pred_taken,
    input  wire [7:0]          imm,
    input  wire [ADDR_W-1:0]   fallback_pc,
    input  wire [ADDR_W-1:0]   reg_target,   
    input  wire                zero,
    input  wire                greater,
    input  wire [ADDR_W-1:0]   epc,

    output wire                reti_taken,
    output wire                is_branch_instr,
    output wire                branch_taken,
    output wire [ADDR_W-1:0]   actual_target,
    output wire                ex_mispredict,
    output wire [ADDR_W-1:0]   ex_recovery_pc
);

    assign is_branch_instr = (opcode == `OP_JMP) | (opcode == `OP_JZ) |
                             (opcode == `OP_JNZ) | (opcode == `OP_JGT) |
                             (opcode == `OP_JAL) | (opcode == `OP_JR);
                             
    assign reti_taken = (opcode == `OP_RETI) || (opcode == `OP_ERET);

    assign branch_taken = pc_src & (
                          (opcode == `OP_JMP) |
                          (opcode == `OP_JAL) |
                          (opcode == `OP_JR)  |
                          (opcode == `OP_JZ  & zero) |
                          (opcode == `OP_JNZ & ~zero) |
                          (opcode == `OP_JGT & greater));

    assign actual_target  = reti_taken ? ((opcode == `OP_ERET) ? (epc + 1'b1) : epc) :
                            (opcode == `OP_JR) ? reg_target : (ex_pc + imm);

    assign ex_mispredict  = (is_branch_instr && (pred_taken != branch_taken)) | reti_taken | (opcode == `OP_JR);
    assign ex_recovery_pc = reti_taken ? actual_target : (branch_taken ? actual_target : fallback_pc);

endmodule
