`timescale 1ns / 1ps

module ControlUnit (
    input  wire [4:0] opcode,
    input  wire       zero,
    input  wire       greater,
    output reg        reg_we,
    output reg        mem_we,
    output reg  [1:0] alu_b_src,
    output reg  [1:0] res_src,
    output reg        pc_src,
    output reg        rs1_src,
    output reg        rs2_src,
    output reg        mem_addr_src,
    output reg        base_reg_src,
    output reg        halt
);
    always @(*) begin
        reg_we       = 0;
        mem_we       = 0;
        pc_src       = 0;
        halt         = 0;
        alu_b_src    = 2'b00;
        res_src      = 2'b00;
        mem_addr_src = 0; //not used as of now
        base_reg_src = 0;
        rs1_src      = 0;
        rs2_src      = 0;

        case(opcode)
            5'b0_0000, 5'b0_0001, 5'b0_0010, 5'b0_0011,
            5'b0_0100, 5'b0_0101, 5'b0_0110, 5'b0_1111: begin
                reg_we = 1;
            end
            5'b1_0000, 5'b1_0001, 5'b1_0010, 5'b1_0011: begin
                reg_we = 1;
            end
            5'b0_0111: begin
                reg_we  = 1;
                res_src = 2'b10;
            end
            5'b0_1000: begin
                reg_we       = 1;
                res_src      = 2'b01;
                base_reg_src = 0;
            end
            5'b0_1001: begin
                mem_we       = 1;
                rs1_src      = 1;
                rs2_src      = 1;
                base_reg_src = 1;
            end
            5'b0_1010: begin
                pc_src = 1;
            end
            5'b0_1011: begin
                alu_b_src = 2'b01;
                pc_src    = (zero) ? 1 : 0;
                rs1_src   = 1;
            end
            5'b0_1100: begin
                alu_b_src = 2'b01;
                pc_src    = (~zero) ? 1 : 0;
                rs1_src   = 1;
            end
            5'b0_1101: begin
                alu_b_src = 2'b01;
                pc_src    = (greater) ? 1 : 0;
                rs1_src   = 1;
            end
            5'b0_1110: begin
                reg_we    = 1;
                alu_b_src = 2'b10;
            end
            5'b1_1111: begin
                halt = 1;
            end
            default: ;
        endcase
    end
endmodule
