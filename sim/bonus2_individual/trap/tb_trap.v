`timescale 1ns / 1ps

module tb_trap;
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
    wire [7:0] saved_epc = dut.u_DMEM.memory[8'hDD];
    wire [7:0] blocked_store = dut.u_DMEM.memory[8'hCC];

    initial begin
        $dumpfile("sim/bonus2_individual/trap/trap.vcd");
        $dumpvars(0, clk, rst, pc, cause, epc, halted, saved_epc, blocked_store);
        #1 $readmemh("sim/bonus2_individual/trap/trap.hex", dut.u_IMEM.memory);
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (120) @(posedge clk);
        if (!halted || cause !== 2'd3 || epc !== 8'd1 ||
            saved_epc !== 8'd1 || blocked_store !== 8'd0)
            $fatal(1, "TRAP test failed");
        $display("PASS TRAP: EPC=1 CAUSE=3 mem[DD]=01 mem[CC]=00");
        $finish;
    end
endmodule
