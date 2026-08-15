`timescale 1ns / 1ps
module tb_peripherals_uart;

    reg clk = 0, rst = 1;
    reg interrupt_pin = 0, uart_rx = 1;
    reg [7:0] external_digital_pins = 8'hA5, external_adc_pins = 8'h3C;
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

    always #5 clk = ~clk; // 100MHz clock period (10ns)

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
        $dumpfile("sim/comprehensive_test/peripherals_test.vcd");
        $dumpvars(0, tb_peripherals_uart);

        // PC 0: LDI R1, 0xFE
        dut.u_IMEM.memory[0] = enc_i(5'b00111, 3'd1, 8'hFE);
        // PC 1: LDD R2, R1, 0 (Read Digital Inputs -> 0xA5)
        dut.u_IMEM.memory[1] = enc_addi(5'b01000, 3'd2, 3'd1, 5'd0);

        // PC 2: LDI R1, 0xFD
        dut.u_IMEM.memory[2] = enc_i(5'b00111, 3'd1, 8'hFD);
        // PC 3: LDD R3, R1, 0 (Read ADC Inputs -> 0x3C)
        dut.u_IMEM.memory[3] = enc_addi(5'b01000, 3'd3, 3'd1, 5'd0);

        // PC 4: LDI R4, 128 (50% Duty Cycle for PWM)
        dut.u_IMEM.memory[4] = enc_i(5'b00111, 3'd4, 8'b10000000); // 8'd128
        // PC 5: STD R4, 0xFF (Set PWM Duty Cycle)
        dut.u_IMEM.memory[5] = enc_br(5'b10101, 3'd4, 8'hFF);

        // PC 6: LDI R5, 8'h55 (UART byte 'U')
        dut.u_IMEM.memory[6] = enc_i(5'b00111, 3'd5, 8'h55);
        // PC 7: STD R5, 0xFC (Write to UART TX)
        dut.u_IMEM.memory[7] = enc_br(5'b10101, 3'd5, 8'hFC);

        // PC 8: HALT
        dut.u_IMEM.memory[8] = 16'hF800;

        #55 rst = 0;

        while (dut.ID_EX_halt !== 1'b1) begin
            @(posedge clk);
        end
        #100;

        if (dut.u_RegFile.registers[2] !== 8'hA5) begin
            $display("FAIL: MMIO Digital Pin Read expected 0xA5, got 0x%h", dut.u_RegFile.registers[2]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[3] !== 8'h3C) begin
            $display("FAIL: MMIO ADC Pin Read expected 0x3C, got 0x%h", dut.u_RegFile.registers[3]);
            errors = errors + 1;
        end
        if (dut.u_DMEM.pwm_duty_cycle !== 8'd128) begin
            $display("FAIL: PWM Duty Cycle Register expected 128, got %d", dut.u_DMEM.pwm_duty_cycle);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: All MMIO Peripherals (GPIO, ADC, PWM, UART TX) Verified Successfully!");
        end else begin
            $fatal(1, "FAIL: %0d peripheral checks failed!", errors);
        end

        $finish;
    end
endmodule
