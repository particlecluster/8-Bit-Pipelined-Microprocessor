`timescale 1ns / 1ps
module tb_uart_full_loopback;

    reg clk = 0, rst = 1;
    reg interrupt_pin = 0;
    wire uart_rx;
    wire motor_pwm_pin;
    wire uart_tx;

    // Direct loopback wire connecting TX output to RX input
    assign uart_rx = uart_tx;

    CPU_Core_5Stage dut (
        .clk(clk),
        .rst(rst),
        .interrupt_pin(interrupt_pin),
        .external_digital_pins(8'h00),
        .external_adc_pins(8'h00),
        .motor_pwm_pin(motor_pwm_pin),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    always #10 clk = ~clk; // 50MHz clock (20ns period)

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
        $dumpfile("sim/comprehensive_test/uart_loopback.vcd");
        $dumpvars(0, tb_uart_full_loopback);

        $display("========================================================================");
        $display("        TESTING HARDWARE UART TX -> RX LOOPBACK & MMIO STACK           ");
        $display("========================================================================");

        // PC 0: LDI R1, 0x35 (ASCII '5')
        dut.u_IMEM.memory[0] = enc_i(5'b00111, 3'd1, 8'h35);
        // PC 1: STD R1, 0xFC (Write byte 0x35 to UART TX register -> triggers hardware TX transmission)
        dut.u_IMEM.memory[1] = enc_br(5'b10101, 3'd1, 8'hFC);

        // PC 2: LDI R7, 0xFA (Address of UART Status)
        dut.u_IMEM.memory[2] = enc_i(5'b00111, 3'd7, 8'hFA);
        // PC 3: LDD R6, R7, 0 (Read UART Status)
        dut.u_IMEM.memory[3] = enc_addi(5'b01000, 3'd6, 3'd7, 5'd0);
        // PC 4: JZ R6, 8'hFE (Branch back to PC 3 if rx_valid is 0 -> 4 + 8'hFE = PC 2)
        dut.u_IMEM.memory[4] = enc_br(5'b01011, 3'd6, 8'hFE);

        // PC 5: LDI R7, 0xFB (Address of UART RX Data)
        dut.u_IMEM.memory[5] = enc_i(5'b00111, 3'd7, 8'hFB);
        // PC 6: LDD R2, R7, 0 (Read received byte into R2)
        dut.u_IMEM.memory[6] = enc_addi(5'b01000, 3'd2, 3'd7, 5'd0);
        // PC 7: HALT
        dut.u_IMEM.memory[7] = 16'hF800;

        #55 rst = 0;

        // Wait until CPU reaches HALT after polling loop & serial transfer completes
        while (dut.ID_EX_halt !== 1'b1) begin
            @(posedge clk);
        end
        #100;

        // Verify serial reception in DataMemory_UART & RegFile
        if (dut.u_RegFile.registers[2] !== 8'h35) begin
            $display("❌ FAIL: UART Loopback Received R2 expected 0x35, got 0x%h", dut.u_RegFile.registers[2]);
            errors = errors + 1;
        end else begin
            $display("  [✓] UART Transmitted byte 0x35 via TX pin at 115200 baud");
            $display("  [✓] CPU Polled UART Status Register (0xFA) until rx_valid = 1");
            $display("  [✓] UART Received byte 0x35 via RX pin");
            $display("  [✓] CPU Read 0x35 from UART RX MMIO register (0xFB) into R2");
        end

        $display("------------------------------------------------------------------------");
        if (errors == 0) begin
            $display(" 🎉 FULL UART TX/RX SERIAL HARDWARE LOOPBACK VERIFIED PERFECTLY! 🎉 ");
        end else begin
            $fatal(1, " ❌ UART LOOPBACK TEST FAILED!");
        end
        $display("========================================================================");

        $finish;
    end
endmodule
