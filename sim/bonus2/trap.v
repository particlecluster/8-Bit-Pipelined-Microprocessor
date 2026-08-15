`timescale 1ns / 1ps
module tb_bonus2;
    reg clk = 0, rst = 1, interrupt_pin = 0, uart_rx = 1;
    reg [7:0] external_digital_pins = 0, external_adc_pins = 0;
    wire pwm0, pwm1, pwm2, tx0, tx1, tx2;
    CPU_Core_5Stage trap_cpu     (.clk(clk), .rst(rst), .interrupt_pin(interrupt_pin), .external_digital_pins(external_digital_pins), .external_adc_pins(external_adc_pins), .motor_pwm_pin(pwm2), .uart_rx(uart_rx), .uart_tx(tx2));
    always #5 clk = ~clk;

    wire [7:0] trap_pc = trap_cpu.pc_if;
    wire [1:0] trap_cause = trap_cpu.exception_cause;
    wire [7:0] trap_epc = trap_cpu.exception_epc;
    wire [7:0] saved_epc = trap_cpu.u_DMEM.memory[8'hDD];
    wire [7:0] blocked_trap_store = trap_cpu.u_DMEM.memory[8'hCC];
    wire [7:0] register1 = trap_cpu.u_RegFile.registers[1];
    wire [7:0] register2 = trap_cpu.u_RegFile.registers[2];
    wire [7:0] mem0x10 = trap_cpu.u_DMEM.memory[8'h10];

    initial begin
        $dumpfile("sim/bonus2/trap.vcd");
        $dumpvars(0, clk, rst, trap_pc, trap_cause, trap_epc, saved_epc, blocked_trap_store, register1, register2, mem0x10);
        #1;
        $readmemh("sim/bonus2/bonus_trap.hex", trap_cpu.u_IMEM.memory);
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (150) @(posedge clk);
        if (!trap_cpu.ID_EX_halt || trap_cause !== 3 || trap_epc !== 1 || saved_epc !== 1 || blocked_trap_store !== 0)
            $fatal(1, "TRAP exception test failed");
        $display("PASS Bonus 2: TRAP verified");
        $finish;
    end
endmodule
