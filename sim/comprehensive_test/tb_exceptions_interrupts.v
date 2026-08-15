`timescale 1ns / 1ps
module tb_exceptions_interrupts;

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

    function [15:0] enc_i(input [4:0] op, input [2:0] rd, input [7:0] imm);
        enc_i = {op, rd, imm};
    endfunction

    function [15:0] enc_r(input [4:0] op, input [2:0] rd, input [2:0] rs1, input [2:0] rs2);
        enc_r = {op, rd, rs1, rs2, 2'b00};
    endfunction

    integer errors = 0;

    initial begin
        $dumpfile("sim/comprehensive_test/exceptions_test.vcd");
        $dumpvars(0, tb_exceptions_interrupts);

        // --- Main Program ---
        // PC 0: LDI R1, 150
        dut.u_IMEM.memory[0] = enc_i(5'b00111, 3'd1, 8'd150);
        // PC 1: LDI R2, 120
        dut.u_IMEM.memory[1] = enc_i(5'b00111, 3'd2, 8'd120);
        // PC 2: ADD R3, R1, R2 -> Overflows! (150+120=270 > 255) -> Triggers Overflow Exception (cause=1, epc=2)
        dut.u_IMEM.memory[2] = enc_r(5'b00000, 3'd3, 3'd1, 3'd2);
        // PC 3: LDI R6, 88
        dut.u_IMEM.memory[3] = enc_i(5'b00111, 3'd6, 8'd88);
        // PC 4: HALT
        dut.u_IMEM.memory[4] = 16'hF800;

        // --- Exception / Interrupt Vector at 0x80 ---
        // PC 0x80 (128): MFC0 R4, 0 (Read exception_cause into R4)
        dut.u_IMEM.memory[8'h80] = enc_i(5'b11010, 3'd4, 8'd0);
        // PC 0x81 (129): MFC0 R5, 1 (Read exception_epc into R5)
        dut.u_IMEM.memory[8'h81] = enc_i(5'b11010, 3'd5, 8'd1);
        // PC 0x82 (130): ERET (Return from Exception)
        dut.u_IMEM.memory[8'h82] = {5'b11001, 11'd0}; // OP_ERET

        #55 rst = 0;

        while (dut.ID_EX_halt !== 1'b1) begin
            @(posedge clk);
        end
        #50;

        if (dut.u_RegFile.registers[4] !== 8'd1) begin
            $display("FAIL: Exception Cause (Overflow) expected 1, got %d", dut.u_RegFile.registers[4]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[5] !== 8'd2) begin
            $display("FAIL: Exception EPC expected 2, got %d", dut.u_RegFile.registers[5]);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: All Exceptions (Overflow, CP0, ERET) Verified Successfully!");
        end else begin
            $fatal(1, "FAIL: %0d exception checks failed!", errors);
        end

        $finish;
    end
endmodule
