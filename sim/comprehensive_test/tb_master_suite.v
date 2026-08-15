`timescale 1ns / 1ps
module tb_master_suite;

    reg clk = 0, rst = 1;
    reg interrupt_pin = 0, uart_rx = 1;
    reg [7:0] external_digital_pins = 8'hBE, external_adc_pins = 8'hEF;
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
        $dumpfile("sim/comprehensive_test/master_suite.vcd");
        $dumpvars(0, tb_master_suite);

        $display("========================================================================");
        $display("   STARTING COMPREHENSIVE 5-STAGE CPU CORE MASTER VERIFICATION SUITE   ");
        $display("========================================================================");

        // --- Integrated Master Benchmark ---
        // PC 0: LDI R1, 10
        dut.u_IMEM.memory[0] = enc_i(5'b00111, 3'd1, 8'd10);
        // PC 1: LDI R2, 20
        dut.u_IMEM.memory[1] = enc_i(5'b00111, 3'd2, 8'd20);
        // PC 2: ADD R3, R1, R2 -> 30 (Forwarding EX->EX)
        dut.u_IMEM.memory[2] = enc_r(5'b00000, 3'd3, 3'd1, 3'd2);
        // PC 3: MUL R4, R3, R1 -> 300 & 0xFF = 44
        dut.u_IMEM.memory[3] = enc_r(5'b10000, 3'd4, 3'd3, 3'd1);
        // PC 4: MAC R4, R1, R2 -> 44 + (10*20) = 244
        dut.u_IMEM.memory[4] = enc_r(5'b10001, 3'd4, 3'd1, 3'd2);
        // PC 5: STD R4, 0x60 -> mem[0x60] = 244
        dut.u_IMEM.memory[5] = enc_br(5'b10101, 3'd4, 8'h60);
        // PC 6: LDI R7, 0x60
        dut.u_IMEM.memory[6] = enc_i(5'b00111, 3'd7, 8'h60);
        // PC 7: LDD R5, R7, 0 -> 244 (Load-Use Stall)
        dut.u_IMEM.memory[7] = enc_addi(5'b01000, 3'd5, 3'd7, 5'd0);
        // PC 8: SUB R6, R5, R3 -> 244 - 30 = 214
        dut.u_IMEM.memory[8] = enc_r(5'b00001, 3'd6, 3'd5, 3'd3);
        // PC 9: STD R6, 0xFF (Set PWM Duty Cycle to 214)
        dut.u_IMEM.memory[9] = enc_br(5'b10101, 3'd6, 8'hFF);
        // PC 10: HALT
        dut.u_IMEM.memory[10] = 16'hF800;

        #55 rst = 0;

        while (dut.ID_EX_halt !== 1'b1) begin
            @(posedge clk);
        end
        #100;

        // Verify Results
        if (dut.u_RegFile.registers[3] !== 8'd30) begin
            $display("❌ MASTER FAIL: R3 expected 30, got %d", dut.u_RegFile.registers[3]);
            errors = errors + 1;
        end else $display("  [✓] Forwarding & ADD: R3 = 30");

        if (dut.u_RegFile.registers[4] !== 8'd244) begin
            $display("❌ MASTER FAIL: MAC R4 expected 244, got %d", dut.u_RegFile.registers[4]);
            errors = errors + 1;
        end else $display("  [✓] Multiply-Accumulate (MAC): R4 = 244");

        if (dut.u_DMEM.memory[8'h60] !== 8'd244) begin
            $display("❌ MASTER FAIL: Store Data expected 244, got %d", dut.u_DMEM.memory[8'h60]);
            errors = errors + 1;
        end else $display("  [✓] Memory Store (STD): mem[0x60] = 244");

        if (dut.u_RegFile.registers[5] !== 8'd244) begin
            $display("❌ MASTER FAIL: Load Data expected 244, got %d", dut.u_RegFile.registers[5]);
            errors = errors + 1;
        end else $display("  [✓] Load-Use Hazard & Load (LDD): R5 = 244");

        if (dut.u_RegFile.registers[6] !== 8'd214) begin
            $display("❌ MASTER FAIL: SUB R6 expected 214, got %d", dut.u_RegFile.registers[6]);
            errors = errors + 1;
        end else $display("  [✓] ALU Subtraction (SUB): R6 = 214");

        if (dut.u_DMEM.pwm_duty_cycle !== 8'd214) begin
            $display("❌ MASTER FAIL: PWM Duty Cycle expected 214, got %d", dut.u_DMEM.pwm_duty_cycle);
            errors = errors + 1;
        end else $display("  [✓] MMIO PWM Peripheral Output: duty_cycle = 214");

        $display("------------------------------------------------------------------------");
        if (errors == 0) begin
            $display(" 🎉 ALL MASTER SYSTEM VERIFICATION CHECKS PASSED SUCCESSFULLY! 🎉 ");
        end else begin
            $fatal(1, " ❌ MASTER SYSTEM VERIFICATION FAILED WITH %0d ERRORS!", errors);
        end
        $display("========================================================================");

        $finish;
    end
endmodule
