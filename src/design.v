`timescale 1ns / 1ps

// --- 1. Program Counter ---
module ProgramCounter (
    input  wire       clk,
    input  wire       rst,
    input  wire       halt,
    input  wire [7:0] next_pc, 
    output reg  [7:0] pc
);
    always @(posedge clk) begin
        if (rst)       pc <= 8'b0000_0000;
        else if (halt) pc <= pc;
        else           pc <= next_pc;
    end
endmodule

// --- 2. Upgraded ALU ---
module ALU (
    input  wire [7:0] a,            // Rs1
    input  wire [7:0] b,            // Rs2 (or Immediate)
    input  wire [7:0] rd_val,       // Current value of Rd (for MAC)
    input  wire [4:0] alu_control,  // 5-bit control {EXT, OPCODE}
    output reg  [7:0] result, 
    output wire       zero, 
    output wire       greater
);
    
    // Combinational Multiplier (Infers a DSP block in Vivado)
    wire [15:0] mul_prod = a * b;

    always @(*) begin
        case (alu_control)
            // --- BASE ISA ---
            5'b0_0000, 
            5'b0_1110: result = a + b;                                               // ADD and ADDI
            5'b0_0001: result = a - b;                                               // SUB
            5'b0_0010: result = a & b;                                               // AND
            5'b0_0011: result = a | b;                                               // ORR
            5'b0_0100: result = a ^ b;                                               // XOR
            5'b0_0101: result = a << b[2:0];                                         // SHL 
            5'b0_0110: result = a >> b[2:0];                                         // SHR
            5'b0_1111: result = ($signed(a) < $signed(b)) ? 8'b0000_0001 : 8'b0000_0000; // SLT
            
            // --- EXTENDED ISA ---
            5'b1_0000: result = mul_prod[7:0];                                       // MUL
            5'b1_0001: result = rd_val + mul_prod[7:0];                              // MAC (Accumulate)
            5'b1_0010: result = (a << b[2:0]) | (a >> (8 - b[2:0]));                 // ROL
            5'b1_0011: result = (a >> b[2:0]) | (a << (8 - b[2:0]));                 // ROR
            
            default:   result = 8'b0000_0000;
        endcase
    end

    // Branching Flags
    assign zero    = (a == b);
    assign greater = ($signed(a) > $signed(b));
endmodule

// --- 3. Register File ---
module RegisterFile (
    input  wire       clk, 
    input  wire       we,
    input  wire [2:0] rs1, 
    input  wire [2:0] rs2, 
    input  wire [2:0] rd,
    input  wire [7:0] wd, 
    output wire [7:0] rd1, 
    output wire [7:0] rd2, 
    output wire [7:0] rd3   // Third read port for MAC
);
    reg [7:0] registers [0:7];

    integer i;
    initial begin
        for (i = 0; i < 8; i = i + 1) begin
            registers[i] = 8'h00;
        end
    end
    
    assign rd1 = (rs1 == 3'b000) ? 8'h00 : registers[rs1];
    assign rd2 = (rs2 == 3'b000) ? 8'h00 : registers[rs2];
    assign rd3 = (rd  == 3'b000) ? 8'h00 : registers[rd];

    always @(posedge clk) begin
        if (we && (rd != 3'b000)) registers[rd] <= wd;
    end
endmodule

// --- 4. Data Memory & MMIO ---
module DataMemory (
    input  wire       clk, 
    input  wire       we,
    input  wire [7:0] addr, 
    input  wire [7:0] wd, 
    output wire [7:0] rd,
    output reg  [7:0] pwm_duty_cycle // Motor Latch
);
    reg [7:0] memory [0:254]; 

    // Reads to 0xFF return 0. Otherwise, read standard SRAM.
    assign rd = (addr == 8'hFF) ? 8'h00 : memory[addr];

    always @(posedge clk) begin
        if (we) begin
            if (addr == 8'hFF) pwm_duty_cycle <= wd;
            else               memory[addr] <= wd;
        end
    end
endmodule

// --- 5. Instruction Memory ---
module InstructionMemory (
    input  wire [7:0] pc, 
    output wire [15:0] instr
);
    reg [15:0] memory [0:255];
    initial begin
        $readmemh("program.hex", memory); 
    end
    assign instr = memory[pc];
endmodule

// --- 6. Control Unit ---
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
    output reg  [1:0] addr_src, // NEW: 00=imm, 01=LOAD, 10=STORE
    output reg        halt
);

    always @(*) begin
        // Default assignments
        reg_we    = 0; 
        mem_we    = 0; 
        pc_src    = 0; 
        halt      = 0;
        alu_b_src = 2'b00; 
        res_src   = 2'b00; 
        addr_src  = 2'b00;
        rs1_src   = 0; 
        rs2_src   = 0; 

        case(opcode)
            // Base R-type ALU
            5'b0_0000, 5'b0_0001, 5'b0_0010, 5'b0_0011,
            5'b0_0100, 5'b0_0101, 5'b0_0110, 5'b0_1111: begin
                reg_we = 1;
            end

            // EXT R-type ALU
            5'b1_0000, 5'b1_0001, 5'b1_0010, 5'b1_0011: begin
                reg_we = 1;
            end

            // LDI
            5'b0_0111: begin
                reg_we = 1; 
                res_src = 2'b10;
            end

            // LOAD
            5'b0_1000: begin
                reg_we = 1; 
                res_src = 2'b01;
                addr_src = 2'b01; // Pick LOAD addressing
            end

            // STORE
            5'b0_1001: begin
                mem_we   = 1; 
                rs1_src  = 1; 
                rs2_src  = 1;
                addr_src = 2'b10; // Pick STORE addressing
            end

            // JMP
            5'b0_1010: begin
                pc_src = 1;
            end

            // Branches
            5'b0_1011: begin alu_b_src = 2'b01; pc_src = (zero)    ? 1 : 0; rs1_src = 1; end
            5'b0_1100: begin alu_b_src = 2'b01; pc_src = (~zero)   ? 1 : 0; rs1_src = 1; end
            5'b0_1101: begin alu_b_src = 2'b01; pc_src = (greater) ? 1 : 0; rs1_src = 1; end

            // ADDI
            5'b0_1110: begin
                reg_we    = 1; 
                alu_b_src = 2'b10;
            end

            // HLT 
            5'b1_1111: begin
                halt = 1; 
            end

            // NOP default falls through safely
            default: ; 
        endcase
    end
endmodule

// --- 7. Top-Level CPU ---
module CPU_Core (
    input  wire clk, 
    input  wire rst, 
    output wire motor_pwm_pin
);

    wire system_rst;

    wire [7:0]  pc, next_pc, pc_plus_1;
    wire [15:0] instr;
    wire [7:0]  imm       = instr[7:0];
    wire [7:0]  imm5_sext = {{3{instr[4]}}, instr[4:0]}; 
    
    wire        reg_we, mem_we, pc_src, rs1_src, rs2_src, halt;
    wire [1:0]  alu_b_src, res_src, addr_src;
    wire        zero, greater;

    wire [7:0]  reg_rd1, reg_rd2, reg_rd3, alu_result, mem_rd, reg_write_data, alu_b_in;
    wire [2:0]  read_reg_1, read_reg_2;
    wire [7:0]  mem_addr, motor_duty_cycle, base_reg;

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
        .opcode   (instr[15:11]),
        .zero     (zero),
        .greater  (greater),
        .reg_we   (reg_we),
        .mem_we   (mem_we),
        .alu_b_src(alu_b_src),
        .res_src  (res_src),
        .pc_src   (pc_src),
        .rs1_src  (rs1_src),
        .rs2_src  (rs2_src),
        .addr_src (addr_src),
        .halt     (halt)
    );

    assign read_reg_1 = (rs1_src) ? instr[10:8] : instr[7:5]; 
    assign read_reg_2 = (rs2_src) ? instr[7:5]  : instr[4:2]; 

    // --- NEW: Optimized Memory Address Logic ---
    assign base_reg = (addr_src == 2'b10) ? reg_rd2 : reg_rd1;
    assign mem_addr = (addr_src == 2'b00) ? imm : (base_reg + {3'b000, instr[4:0]});

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
endmodule

// --- 8. Hardware PWM Generator ---
module PWM_Generator (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] duty_cycle, 
    output reg        pwm_out 
);
    reg [7:0] counter;
    always @(posedge clk) begin
        if (rst) begin
            counter <= 8'b0;
            pwm_out <= 1'b0;
        end else begin
            counter <= counter + 1;
            pwm_out <= (counter < duty_cycle) ? 1'b1 : 1'b0;
        end
    end
endmodule

module ResetSynchronizer (
    input wire clk,
    input wire async_rst_in,
    output reg sync_rst_out
);
    reg rst_ff1;

    always @(posedge clk) begin
        rst_ff1 <= async_rst_in;      // Stage 1: Catches the raw signal
        sync_rst_out <= rst_ff1;      // Stage 2: Outputs clean, synchronous signal
    end
endmodule
