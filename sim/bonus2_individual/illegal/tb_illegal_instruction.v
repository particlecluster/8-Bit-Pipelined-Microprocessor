`timescale 1ns / 1ps

module tb_illegal_instruction;
    reg clk = 0, rst = 1, interrupt_pin = 0, uart_rx = 1;
    reg [7:0] external_digital_pins = 0, external_adc_pins = 0;
    wire motor_pwm_pin, uart_tx;

    CPU_Core_5Stage dut (
        .clk(clk), .rst(rst), .interrupt_pin(interrupt_pin), .uart_rx(uart_rx),
        .external_digital_pins(external_digital_pins), .external_adc_pins(external_adc_pins),
        .motor_pwm_pin(motor_pwm_pin), .uart_tx(uart_tx)
    );

    always #5 clk = ~clk;

    wire [7:0] pc = dut.pc_if;
    wire [1:0] cause = dut.exception_cause;
    wire [7:0] epc = dut.exception_epc;
    wire halted = dut.ID_EX_halt;
    wire [7:0] error_marker = dut.u_DMEM.memory[8'hFF];
    wire [7:0] blocked_store = dut.u_DMEM.memory[8'hBB];

    initial begin
        $dumpfile("sim/bonus2_individual/illegal/illegal_instruction.vcd");
        $dumpvars(0, clk, rst, pc, cause, epc, halted, error_marker, blocked_store);
        #1 $readmemh("sim/bonus2_individual/illegal/illegal_instruction.hex", dut.u_IMEM.memory);
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (120) @(posedge clk);
        if (!halted || cause !== 2'd2 || epc !== 8'd2 ||
            error_marker !== 8'hEE || blocked_store !== 8'd0)
            $fatal(1, "Illegal instruction test failed");
        $display("PASS Illegal: EPC=2 CAUSE=2 mem[FF]=EE mem[BB]=00");
        $finish;
    end
endmodule
