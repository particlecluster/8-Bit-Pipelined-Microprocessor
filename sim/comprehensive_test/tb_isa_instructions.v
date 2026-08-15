`timescale 1ns / 1ps
module tb_isa_instructions;

    reg clk = 0, rst = 1;
    reg interrupt_pin = 0, uart_rx = 1;
    reg [7:0] external_digital_pins = 8'h00, external_adc_pins = 8'h00;
    wire motor_pwm_pin, uart_tx;

    CPU_Core_5Stage dut (
        .clk(clk),
        .rst(rst),
        .interrupt_pin(interrupt_pin),
        .external_digital_pins(external_digital_pins),
        .external_adc_pins(external_adc_pins),
        .motor_pwm_pin(motor_pwm_pin),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    always #5 clk = ~clk;

    // Helper encoding functions
    function [15:0] enc_r(input [4:0] op, input [2:0] rd, input [2:0] rs1, input [2:0] rs2);
        enc_r = {op, rd, rs1, rs2, 2'b00};
    endfunction

    function [15:0] enc_i(input [4:0] op, input [2:0] rd, input [7:0] imm);
        enc_i = {op, rd, imm};
    endfunction

    function [15:0] enc_addi(input [4:0] op, input [2:0] rd, input [2:0] rs1, input [4:0] imm5);
        enc_addi = {op, rd, rs1, imm5};
    endfunction

    function [15:0] enc_br(input [4:0] op, input [2:0] rs1, input [7:0] imm);
        enc_br = {op, rs1, imm};
    endfunction

    integer errors = 0;

    initial begin
        $dumpfile("sim/comprehensive_test/isa_test.vcd");
        $dumpvars(0, tb_isa_instructions);

        // Load instruction memory with test program
        // OP_LDI R1, 15
        dut.u_IMEM.memory[0]  = enc_i(5'b00111, 3'd1, 8'd15);
        // OP_LDI R2, 5
        dut.u_IMEM.memory[1]  = enc_i(5'b00111, 3'd2, 8'd5);
        // OP_ADD R3, R1, R2 -> 20
        dut.u_IMEM.memory[2]  = enc_r(5'b00000, 3'd3, 3'd1, 3'd2);
        // OP_SUB R4, R1, R2 -> 10
        dut.u_IMEM.memory[3]  = enc_r(5'b00001, 3'd4, 3'd1, 3'd2);
        // OP_AND R5, R1, R2 -> 15 & 5 = 5
        dut.u_IMEM.memory[4]  = enc_r(5'b00010, 3'd5, 3'd1, 3'd2);
        // OP_OR R6, R1, R2 -> 15 | 5 = 15
        dut.u_IMEM.memory[5]  = enc_r(5'b00011, 3'd6, 3'd1, 3'd2);
        // OP_XOR R7, R1, R2 -> 15 ^ 5 = 10
        dut.u_IMEM.memory[6]  = enc_r(5'b00100, 3'd7, 3'd1, 3'd2);
        // OP_SHL R3, R2, R2 -> 5 << 5 = 160
        dut.u_IMEM.memory[7]  = enc_r(5'b00101, 3'd3, 3'd2, 3'd2);
        // OP_SHR R4, R3, R2 -> 160 >> 5 = 5
        dut.u_IMEM.memory[8]  = enc_r(5'b00110, 3'd4, 3'd3, 3'd2);
        // OP_SLT R5, R2, R1 -> 5 < 15 = 1
        dut.u_IMEM.memory[9]  = enc_r(5'b01111, 3'd5, 3'd2, 3'd1);
        // OP_MUL R6, R1, R2 -> 15 * 5 = 75
        dut.u_IMEM.memory[10] = enc_r(5'b10000, 3'd6, 3'd1, 3'd2);
        // OP_ADDI R7, R1, 7 -> 15 + 7 = 22
        dut.u_IMEM.memory[11] = enc_addi(5'b01110, 3'd7, 3'd1, 5'd7);
        // OP_STD R7, 0x40 -> mem[0x40] = 22
        dut.u_IMEM.memory[12] = enc_br(5'b10101, 3'd7, 8'h40);
        // OP_LDI R1, 0x40
        dut.u_IMEM.memory[13] = enc_i(5'b00111, 3'd1, 8'h40);
        // OP_LDD R3, R1, 0 -> loads mem[R1+0] = mem[0x40] = 22 into R3
        dut.u_IMEM.memory[14] = enc_addi(5'b01000, 3'd3, 3'd1, 5'd0);
        // OP_ROL R4, R1, R2 -> ROL(0x40, 5) = 0x02
        dut.u_IMEM.memory[15] = enc_r(5'b10010, 3'd4, 3'd1, 3'd2);
        // OP_HALT
        dut.u_IMEM.memory[16] = 16'hF800; // OP_HALT

        #55 rst = 0;

        // Wait until HALT
        while (dut.ID_EX_halt !== 1'b1) begin
            @(posedge clk);
        end
        #100;

        // Check Register File & Data Memory Values
        if (dut.u_RegFile.registers[6] !== 8'd75) begin
            $display("FAIL: MUL R6 expected 75, got %d", dut.u_RegFile.registers[6]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[7] !== 8'd22) begin
            $display("FAIL: ADDI R7 expected 22, got %d", dut.u_RegFile.registers[7]);
            errors = errors + 1;
        end
        if (dut.u_DMEM.memory[8'h40] !== 8'd22) begin
            $display("FAIL: DMEM[0x40] expected 22, got %d", dut.u_DMEM.memory[8'h40]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[3] !== 8'd22) begin
            $display("FAIL: LDD R3 expected 22, got %d", dut.u_RegFile.registers[3]);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: All Basic ISA Instructions Verified Successfully!");
        end else begin
            $fatal(1, "FAIL: %0d instruction test checks failed!", errors);
        end

        $finish;
    end
endmodule
