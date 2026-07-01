`timescale 1ns / 1ps

module CPU_Core (
    input  wire clk,
    input  wire rst,
    output wire motor_pwm_pin
);
    wire system_rst;
    
    wire [7:0]  pc;
    wire [7:0]  next_pc;
    wire [7:0]  pc_plus_1;
    
    wire [15:0] instr;
    wire [7:0]  imm = instr[7:0];
    
    wire [7:0]  imm5_sext;
    wire [7:0]  imm5_zext;
    
    wire        reg_we;
    wire        mem_we;
    wire        pc_src;
    wire        rs1_src;
    wire        rs2_src;
    wire        halt;
    wire        base_reg_src;
    wire        mem_addr_src;
    
    wire [1:0]  alu_b_src;
    wire [1:0]  res_src;
    wire [1:0]  addr_src;
    
    wire        zero;
    wire        greater;
    
    wire [7:0]  reg_rd1;
    wire [7:0]  reg_rd2;
    wire [7:0]  reg_rd3;
    wire [7:0]  alu_result;
    wire [7:0]  mem_rd;
    wire [7:0]  reg_write_data;
    wire [7:0]  alu_b_in;
    
    wire [2:0]  read_reg_1;
    wire [2:0]  read_reg_2;
    
    wire [7:0]  mem_addr;
    wire [7:0]  motor_duty_cycle;
    wire [7:0]  base_reg;

    assign pc_plus_1 = pc + 1;
    assign next_pc   = (pc_src) ? imm : pc_plus_1;

    ProgramCounter u_PC (
        .clk(clk),
        .rst(system_rst),
        .halt(halt),
        .next_pc(next_pc),
        .pc(pc)
    );

    ResetSynchronizer u_RstSync (
        .clk(clk),
        .async_rst_in(rst),
        .sync_rst_out(system_rst)
    );

    InstructionMemory u_IMEM (
        .pc(pc),
        .instr(instr)
    );

    ControlUnit u_CU (
        .opcode(instr[15:11]),
        .zero(zero),
        .greater(greater),
        .reg_we(reg_we),
        .mem_we(mem_we),
        .alu_b_src(alu_b_src),
        .res_src(res_src),
        .pc_src(pc_src),
        .rs1_src(rs1_src),
        .rs2_src(rs2_src),
        .mem_addr_src(mem_addr_src),
        .base_reg_src(base_reg_src),
        .halt(halt)
    );

    assign read_reg_1 = (rs1_src) ? instr[10:8] : instr[7:5];
    assign read_reg_2 = (rs2_src) ? instr[7:5]  : instr[4:2];

    assign base_reg = (base_reg_src) ? reg_rd2 : reg_rd1;
    assign mem_addr = (mem_addr_src) ? imm : (base_reg + imm5_zext);

    assign reg_write_data = (res_src == 2'b00) ? alu_result :
                            (res_src == 2'b01) ? mem_rd : imm;

    RegisterFile u_RegFile (
        .clk(clk),
        .we(reg_we),
        .rs1(read_reg_1),
        .rs2(read_reg_2),
        .rd(instr[10:8]),
        .wd(reg_write_data),
        .rd1(reg_rd1),
        .rd2(reg_rd2),
        .rd3(reg_rd3)
    );

    assign alu_b_in = (alu_b_src == 2'b00) ? reg_rd2 :
                      (alu_b_src == 2'b01) ? 8'h00 : imm5_sext;

    ALU u_ALU (
        .a(reg_rd1),
        .b(alu_b_in),
        .rd_val(reg_rd3),
        .alu_control(instr[15:11]),
        .result(alu_result),
        .zero(zero),
        .greater(greater)
    );

    DataMemory u_DMEM (
        .clk(clk),
        .we(mem_we),
        .addr(mem_addr),
        .wd(reg_rd1),
        .rd(mem_rd),
        .pwm_duty_cycle(motor_duty_cycle)
    );

    PWM_Generator u_PWM (
        .clk(clk),
        .rst(system_rst),
        .duty_cycle(motor_duty_cycle),
        .pwm_out(motor_pwm_pin)
    );

    Extender u_EXT (
        .imm5(imm[4:0]),
        .imm5_sext(imm5_sext),
        .imm5_zext(imm5_zext)
    );

endmodule
