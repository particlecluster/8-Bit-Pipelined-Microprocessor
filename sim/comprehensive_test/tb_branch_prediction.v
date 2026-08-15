`timescale 1ns / 1ps
module tb_branch_prediction;

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

    function [15:0] enc_br(input [4:0] op, input [2:0] rs1, input [7:0] imm);
        enc_br = {op, rs1, imm};
    endfunction

    function [15:0] enc_jal(input [4:0] op, input [2:0] rd, input [7:0] imm);
        enc_jal = {op, rd, imm};
    endfunction

    function [15:0] enc_jr(input [4:0] op, input [2:0] rs1);
        enc_jr = {op, rs1, 8'h00};
    endfunction

    integer errors = 0;

    initial begin
        $dumpfile("sim/comprehensive_test/branch_test.vcd");
        $dumpvars(0, tb_branch_prediction);

        // Subroutine and Branch Test Program:
        // PC 0: LDI R1, 5
        dut.u_IMEM.memory[0] = enc_i(5'b00111, 3'd1, 8'd5);
        // PC 1: JAL R7, 5 -> Jump to PC 6, store PC 2 in R7
        dut.u_IMEM.memory[1] = enc_jal(5'b10110, 3'd7, 8'd5);
        // PC 2: (Return Point) LDI R2, 100
        dut.u_IMEM.memory[2] = enc_i(5'b00111, 3'd2, 8'd100);
        // PC 3: JNZ R1, 4 -> Jump to PC 8 (R1=5, taken)
        dut.u_IMEM.memory[3] = enc_br(5'b01100, 3'd1, 8'd5);
        // PC 4: (Should be skipped) LDI R3, 99
        dut.u_IMEM.memory[4] = enc_i(5'b00111, 3'd3, 8'd99);
        // PC 5: HALT
        dut.u_IMEM.memory[5] = 16'hF800;

        // --- Subroutine Body ---
        // PC 6: ADDI R1, R1, 10 -> R1 = 15
        dut.u_IMEM.memory[6] = {5'b01110, 3'd1, 3'd1, 5'd10};
        // PC 7: JR R7 -> Jump to PC 2
        dut.u_IMEM.memory[7] = enc_jr(5'b10111, 3'd7);

        // --- Target of JNZ ---
        // PC 8: LDI R4, 42
        dut.u_IMEM.memory[8] = enc_i(5'b00111, 3'd4, 8'd42);
        // PC 9: JMP 5 -> Jump to HALT at PC 5 (relative offset 5 - 9 = -4 or absolute target ex_pc+imm = 9 + 8'hFC = 5)
        // Note: BRU computes actual_target = ex_pc + imm (imm sign extended or 8-bit wrap around)
        // 9 + 8'hFC = 5
        dut.u_IMEM.memory[9] = enc_br(5'b01010, 3'd0, 8'hFC);

        #55 rst = 0;

        while (dut.ID_EX_halt !== 1'b1) begin
            @(posedge clk);
        end
        #50;

        if (dut.u_RegFile.registers[7] !== 8'd2) begin
            $display("FAIL: JAL Link Register R7 expected 2, got %d", dut.u_RegFile.registers[7]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[1] !== 8'd15) begin
            $display("FAIL: Subroutine Execution R1 expected 15, got %d", dut.u_RegFile.registers[1]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[2] !== 8'd100) begin
            $display("FAIL: JR Return Execution R2 expected 100, got %d", dut.u_RegFile.registers[2]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[3] === 8'd99) begin
            $display("FAIL: Mispredicted/Skipped instruction at PC 4 was executed!");
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[4] !== 8'd42) begin
            $display("FAIL: Conditional JNZ Target R4 expected 42, got %d", dut.u_RegFile.registers[4]);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: All Branch Prediction, JAL/JR, & Flush Features Verified Successfully!");
        end else begin
            $fatal(1, "FAIL: %0d branch/flush checks failed!", errors);
        end

        $finish;
    end
endmodule
