`timescale 1ns / 1ps

module tb_overflow;
    reg clk = 0;
    reg rst = 1;
    reg interrupt_pin = 0;
    reg uart_rx = 1;
    reg [7:0] external_digital_pins = 0;
    reg [7:0] external_adc_pins = 0;
    wire motor_pwm_pin;
    wire uart_tx;

    CPU_Core_5Stage dut (
        .clk(clk), .rst(rst), .interrupt_pin(interrupt_pin), .uart_rx(uart_rx),
        .external_digital_pins(external_digital_pins), .external_adc_pins(external_adc_pins),
        .motor_pwm_pin(motor_pwm_pin), .uart_tx(uart_tx)
    );

    always #5 clk = ~clk;

    wire [7:0] pc = dut.pc_if;
    wire [1:0] cause = dut.exception_cause;
    wire [7:0] epc = dut.exception_epc;
    wire in_exception = dut.in_exception;
    wire halted = dut.ID_EX_halt;
    wire [7:0] clamped_result = dut.u_DMEM.memory[8'hAA];
    wire [7:0] unaffected_result = dut.u_DMEM.memory[8'hAB];

    initial begin
        $dumpfile("sim/bonus2_individual/overflow/overflow.vcd");
        $dumpvars(0, clk, rst, pc, cause, epc, in_exception, halted,
                  clamped_result, unaffected_result);
        #1 $readmemh("sim/bonus2_individual/overflow/overflow.hex", dut.u_IMEM.memory);
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (120) @(posedge clk);
        if (!halted || cause !== 2'd1 || epc !== 8'd2 ||
            clamped_result !== 8'hFF || unaffected_result !== 8'd100)
            $fatal(1, "Overflow test failed");
        $display("PASS Overflow: EPC=2 CAUSE=1 mem[AA]=FF mem[AB]=100");
        $finish;
    end
endmodule
