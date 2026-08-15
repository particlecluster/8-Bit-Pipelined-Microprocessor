`timescale 1ns / 1ps
module tb_hazards_forwarding;

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

    function [15:0] enc_r(input [4:0] op, input [2:0] rd, input [2:0] rs1, input [2:0] rs2);
        enc_r = {op, rd, rs1, rs2, 2'b00};
    endfunction

    function [15:0] enc_i(input [4:0] op, input [2:0] rd, input [7:0] imm);
        enc_i = {op, rd, imm};
    endfunction

    integer errors = 0;

    initial begin
        $dumpfile("sim/comprehensive_test/hazards_test.vcd");
        $dumpvars(0, tb_hazards_forwarding);

        // 1. Back-to-back dependency (EX->EX Forwarding on RS1 and RS2)
        // LDI R1, 10
        dut.u_IMEM.memory[0] = enc_i(5'b00111, 3'd1, 8'd10);
        // LDI R2, 20
        dut.u_IMEM.memory[1] = enc_i(5'b00111, 3'd2, 8'd20);
        // ADD R3, R1, R2 -> 30 (EX->EX forwarding of R1 and R2 from LDI)
        dut.u_IMEM.memory[2] = enc_r(5'b00000, 3'd3, 3'd1, 3'd2);
        // ADD R4, R3, R1 -> 40 (EX->EX forwarding of R3 from ADD)
        dut.u_IMEM.memory[3] = enc_r(5'b00000, 3'd4, 3'd3, 3'd1);
        // ADD R5, R4, R3 -> 70 (EX->EX forwarding of R4, MEM->EX forwarding of R3)
        dut.u_IMEM.memory[4] = enc_r(5'b00000, 3'd5, 3'd4, 3'd3);

        // 2. Load-Use Hazard Stall Test
        // LDD R6, 0x10 (mem[0x10] has initial value 0)
        dut.u_DMEM.memory[8'h10] = 8'd99;
        dut.u_IMEM.memory[5] = enc_i(5'b01000, 3'd6, 8'h10);
        // ADD R7, R6, R1 -> 99 + 10 = 109 (Requires Load-Use stall + MEM->EX forwarding)
        dut.u_IMEM.memory[6] = enc_r(5'b00000, 3'd7, 3'd6, 3'd1);

        // 3. R0 Read protection test (Writes to R0 must be ignored and not forward non-zero)
        // LDI R0, 50 (R0 should remain 0)
        dut.u_IMEM.memory[7] = enc_i(5'b00111, 3'd0, 8'd50);
        // ADD R1, R0, R2 -> 0 + 20 = 20
        dut.u_IMEM.memory[8] = enc_r(5'b00000, 3'd1, 3'd0, 3'd2);

        // OP_HALT
        dut.u_IMEM.memory[9] = 16'hF800;

        #55 rst = 0;

        while (dut.ID_EX_halt !== 1'b1) begin
            @(posedge clk);
        end
        #50;

        if (dut.u_RegFile.registers[3] !== 8'd30) begin
            $display("FAIL: EX->EX Forwarding R3 expected 30, got %d", dut.u_RegFile.registers[3]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[4] !== 8'd40) begin
            $display("FAIL: EX->EX Forwarding R4 expected 40, got %d", dut.u_RegFile.registers[4]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[5] !== 8'd70) begin
            $display("FAIL: Double Forwarding R5 expected 70, got %d", dut.u_RegFile.registers[5]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[7] !== 8'd109) begin
            $display("FAIL: Load-Use Hazard R7 expected 109, got %d", dut.u_RegFile.registers[7]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[0] !== 8'd0) begin
            $display("FAIL: R0 Write Protection expected 0, got %d", dut.u_RegFile.registers[0]);
            errors = errors + 1;
        end
        if (dut.u_RegFile.registers[1] !== 8'd20) begin
            $display("FAIL: R0 Forwarding Protection R1 expected 20, got %d", dut.u_RegFile.registers[1]);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: All Data Hazards & Forwarding Paths Verified Successfully!");
        end else begin
            $fatal(1, "FAIL: %0d hazard/forwarding checks failed!", errors);
        end

        $finish;
    end
endmodule
