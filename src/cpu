// --- 1. Program Counter ---
module ProgramCounter (
    input wire clk,
    input wire rst,
    input wire [7:0] next_pc, 
    output reg [7:0] pc
);
    always @(posedge clk) begin
        if (rst) pc <= 8'b0000_0000;
        else pc <= next_pc;
    end
endmodule

// --- 2. Upgraded ALU (Includes Hardware Multiplier & Rotates) ---
module ALU (
    input wire [7:0] a,            // Rs1
    input wire [7:0] b,            // Rs2 (or Immediate)
    input wire [7:0] rd_val,       // NEW: Current value of Rd (for MAC)
    input wire [4:0] alu_control,  // NEW: 5-bit control {EXT, OPCODE}
    
    output reg [7:0] result, 
    output wire zero, 
    output wire greater
);
    
    // Combinational Multiplier (Infers a DSP block in Vivado)
    wire [15:0] mul_prod = a * b;

    always @(*) begin
        case (alu_control)
            // --- BASE ISA (EXT = 0) ---
            5'b0_0000: result = a + b;       // ADD
            5'b0_0001: result = a - b;       // SUB
            5'b0_0010: result = a & b;       // AND
            5'b0_0011: result = a | b;       // ORR
            5'b0_0100: result = a ^ b;       // XOR
            5'b0_0101: result = a << b[2:0]; // SHL 
            5'b0_0110: result = a >> b[2:0]; // SHR
            
            // --- EXTENDED ISA (EXT = 1) ---
            5'b1_0000: result = mul_prod[7:0];                 // MUL
            5'b1_0001: result = rd_val + mul_prod[7:0];        // MAC (Accumulate)
            5'b1_0010: result = (a << b[2:0]) | (a >> (8 - b[2:0])); // ROL
            5'b1_0011: result = (a >> b[2:0]) | (a << (8 - b[2:0])); // ROR
            
            default: result = 8'b0000_0000;
        endcase
    end

    // Branching Flags (Using signed comparisons as fixed previously)
    assign zero = (a == b);
    assign greater = ($signed(a) > $signed(b));

endmodule

// --- 3. Upgraded Register File (3 Read Ports) ---
module RegisterFile (
    input wire clk, 
    input wire we,

    input wire [2:0] rs1, 
    input wire [2:0] rs2, 
    input wire [2:0] rd,

    input wire [7:0] wd, 
    output wire [7:0] rd1, 
    output wire [7:0] rd2, 
    output wire [7:0] rd3  // NEW: Third read port for the MAC instruction
);
    reg [7:0] registers [0:7];
    
    // Asynchronous Reads
    assign rd1 = registers[rs1];
    assign rd2 = registers[rs2];
    assign rd3 = registers[rd]; // Instantly outputs the current value of Rd

    // Synchronous Write
    always @(posedge clk) begin
        if (we) registers[rd] <= wd;
    end
endmodule


// --- 4. Upgraded Data Memory (With MMIO Motor PWM Latch) ---
module DataMemory (
    input wire clk, 

    input wire we,

    input wire [7:0] addr, 
    input wire [7:0] wd, 
    output wire [7:0] rd,

    output reg [7:0] pwm_duty_cycle // Dedicated output for the motor
);

    reg [7:0] memory [0:254]; 

    // Reads to 0xFF return 0. Otherwise, read standard SRAM.
    assign rd = (addr == 8'hFF) ? 8'h00 : memory[addr];

    always @(posedge clk) begin
        if (we) begin
            if (addr == 8'hFF) begin
                pwm_duty_cycle <= wd; // Write to Motor Latch
            end else begin
                memory[addr] <= wd;   // Write to SRAM
            end
        end
    end
endmodule

// --- 5. Instruction Memory ---
module InstructionMemory (
    input wire [7:0] pc, 
    output wire [15:0] instr
);
    reg [15:0] memory [0:255];
    initial begin
        $readmemh("program.hex", memory); 
    end
    assign instr = memory[pc];
endmodule

// --- 6. Upgraded Control Unit (Handles 5-bit Opcode + EXT) ---
module ControlUnit (
    input wire [4:0] opcode,
    input wire zero,
    input wire greater,
    output reg reg_we,
    output reg mem_we,
    output reg alu_b_src,
    output reg [1:0] res_src,
    output reg pc_src,
    output reg rs1_src    // NEW: 1 = rs1 in [10:8], 0 = rs1 in [7:5]
);

    always @(*) begin
        reg_we = 0; mem_we = 0;
        alu_b_src = 0; res_src = 2'b00; pc_src = 0;
        rs1_src = 0;   // default: R-type, rs1 in [7:5]

        case(opcode)
            // Base R-type ALU — rs1 in [7:5]
            5'b0_0000, 5'b0_0001, 5'b0_0010, 5'b0_0011,
            5'b0_0100, 5'b0_0101, 5'b0_0110: begin
                reg_we = 1;
                rs1_src = 0;
            end

            // EXT R-type ALU (MUL, MAC, ROL, ROR) — rs1 in [7:5]
            5'b1_0000, 5'b1_0001, 5'b1_0010, 5'b1_0011: begin
                reg_we = 1;
                rs1_src = 0;
            end

            // LDI — no rs1 needed, don't care
            5'b0_0111: begin
                reg_we = 1; res_src = 2'b10;
                rs1_src = 0;
            end

            // LOAD — rs1 not used (addr comes from imm), don't care
            5'b0_1000: begin
                reg_we = 1; res_src = 2'b01;
                rs1_src = 0;
            end

            // STORE — rs1 in [10:8] is the register whose value gets stored
            5'b0_1001: begin
                mem_we = 1;
                rs1_src = 1;   // rd field [10:8] holds the source register
            end

            // JMP — no rs1
            5'b0_1010: begin
                pc_src = 1;
                rs1_src = 0;
            end

            // BEQ, BNE, BGT — rs1 in [10:8] (branch compares this reg vs 0)
            5'b0_1011: begin alu_b_src = 1; pc_src = (zero)    ? 1 : 0; rs1_src = 1; end
            5'b0_1100: begin alu_b_src = 1; pc_src = (~zero)   ? 1 : 0; rs1_src = 1; end
            5'b0_1101: begin alu_b_src = 1; pc_src = (greater) ? 1 : 0; rs1_src = 1; end

            default: rs1_src = 0;
        endcase
    end
endmodule

// --- 7. Top-Level CPU ---
module CPU_Core (
    input wire clk, 
    input wire rst, 
    output wire motor_pwm_pin
);
    wire [7:0] pc, next_pc, pc_plus_1;
    wire [15:0] instr;
    wire [7:0] imm = instr[7:0];
    
    wire reg_we, mem_we, alu_b_src, pc_src;
    wire [1:0] res_src;
    wire rs1_src;
    wire zero, greater;

    wire [7:0] reg_rd1, reg_rd2, reg_rd3, alu_result, mem_rd, reg_write_data, alu_b_in;
    wire [2:0] read_reg_1;

    wire [7:0] motor_duty_cycle; // NEW: Wire connecting Memory to PWM block

    assign pc_plus_1 = pc + 1;
    assign next_pc = (pc_src) ? imm : pc_plus_1; 
    
    ProgramCounter u_PC (
        .clk(clk),
        .rst(rst), 
        .next_pc(next_pc), 
        .pc(pc)
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
        .rs1_src  (rs1_src)    // NEW
    );

    assign read_reg_1 = (rs1_src) ? instr[10:8] : instr[7:5]; //for instructions < 1000, rs1 is in bits 7:5
    //assign read_reg_1 = (instr[14:11] >= 4'b1001) ? instr[10:8] : instr[7:5];
    assign reg_write_data = (res_src == 2'b00) ? alu_result :
                            (res_src == 2'b01) ? mem_rd : imm;

    RegisterFile u_RegFile (
        .clk(clk), 
        .we(reg_we), 
        .rs1(read_reg_1), 
        .rs2(instr[4:2]), 
        .rd(instr[10:8]), 
        .wd(reg_write_data), 
        .rd1(reg_rd1), 
        .rd2(reg_rd2), 
        .rd3(reg_rd3)
    );

    assign alu_b_in = (alu_b_src) ? 8'h00 : reg_rd2;
    
    ALU u_ALU (
        .a(reg_rd1), 
        .b(alu_b_in), 
        .rd_val(reg_rd3),               // <--- Pass the accumulator value
        .alu_control(instr[15:11]),     // <--- Pass the 5-bit {EXT, OPCODE}
        .result(alu_result), 
        .zero(zero), 
        .greater(greater)
    );

    DataMemory u_DMEM (
        .clk(clk), 
        .we(mem_we), 
        .addr(imm), 
        .wd(reg_rd1), 
        .rd(mem_rd), 
        .pwm_duty_cycle(motor_duty_cycle)
    );

    PWM_Generator u_PWM (
        .clk(clk), 
        .rst(rst), 
        .duty_cycle(motor_duty_cycle), // Read from wire
        .pwm_out(motor_pwm_pin)        // Drive the physical pin!
    );

endmodule

// --- 8. Hardware PWM Generator ---
module PWM_Generator (
    input wire clk,
    input wire rst,
    input wire [7:0] duty_cycle,  // From address 0xFF
    output reg pwm_out            // To physical FPGA pin -> DRV8833
);

    reg [7:0] counter;

    always @(posedge clk) begin
        if (rst) begin
            counter <= 8'b0000_0000;
            pwm_out <= 1'b0;
        end else begin
            counter <= counter + 1;
            
            // If counter is less than the requested duty cycle, drive pin HIGH.
            // A duty cycle of 255 = 100% HIGH. A duty cycle of 0 = 0% HIGH.
            if (counter < duty_cycle)
                pwm_out <= 1'b1;
            else
                pwm_out <= 1'b0;
        end
    end
endmodule
