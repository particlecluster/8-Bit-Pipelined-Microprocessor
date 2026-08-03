`timescale 1ns / 1ps
module tb_bonus1;
    reg clk = 0, rst = 1, interrupt_pin = 0, uart_rx = 1;
    reg [7:0] external_digital_pins = 0, external_adc_pins = 0;
    wire motor_pwm_pin, uart_tx;
    CPU_Core_5Stage dut (.clk(clk), .rst(rst), .interrupt_pin(interrupt_pin),
        .external_digital_pins(external_digital_pins), .external_adc_pins(external_adc_pins),
        .motor_pwm_pin(motor_pwm_pin), .uart_rx(uart_rx), .uart_tx(uart_tx));
    always #5 clk = ~clk;

    wire [7:0] pc = dut.pc_if;
    wire [15:0] instruction = dut.IF_ID_instr;
    wire [7:0] stack_pointer = dut.u_RegFile.registers[6];
    wire [7:0] link_register = dut.u_RegFile.registers[7];
    wire [7:0] result = dut.u_DMEM.memory[8'hA0];

    initial begin
        $dumpfile("sim/bonus1/bonus1_factorial.vcd");
        $dumpvars(0, clk, rst, pc, instruction, stack_pointer, link_register, result);
        #1 $readmemh("sim/bonus1/bonus_factorial.hex", dut.u_IMEM.memory);
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (250) @(posedge clk);
        if (!dut.ID_EX_halt || result !== 8'd120)
            $fatal(1, "Bonus 1 failed: expected factorial result 120, got %0d", result);
        $display("PASS Bonus 1: recursive factorial result = %0d", result);
        $finish;
    end
endmodule
