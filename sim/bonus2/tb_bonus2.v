`timescale 1ns / 1ps
module tb_bonus2;
    reg clk = 0, rst = 1, interrupt_pin = 0, uart_rx = 1;
    reg [7:0] external_digital_pins = 0, external_adc_pins = 0;
    wire pwm0, pwm1, pwm2, tx0, tx1, tx2;
    CPU_Core_5Stage overflow_cpu (.clk(clk), .rst(rst), .interrupt_pin(interrupt_pin), .external_digital_pins(external_digital_pins), .external_adc_pins(external_adc_pins), .motor_pwm_pin(pwm0), .uart_rx(uart_rx), .uart_tx(tx0));
    CPU_Core_5Stage illegal_cpu  (.clk(clk), .rst(rst), .interrupt_pin(interrupt_pin), .external_digital_pins(external_digital_pins), .external_adc_pins(external_adc_pins), .motor_pwm_pin(pwm1), .uart_rx(uart_rx), .uart_tx(tx1));
    CPU_Core_5Stage trap_cpu     (.clk(clk), .rst(rst), .interrupt_pin(interrupt_pin), .external_digital_pins(external_digital_pins), .external_adc_pins(external_adc_pins), .motor_pwm_pin(pwm2), .uart_rx(uart_rx), .uart_tx(tx2));
    always #5 clk = ~clk;

    wire [7:0] overflow_pc = overflow_cpu.pc_if;
    wire [1:0] overflow_cause = overflow_cpu.exception_cause;
    wire [7:0] overflow_epc = overflow_cpu.exception_epc;
    wire [7:0] clamped = overflow_cpu.u_DMEM.memory[8'hAA];
    wire [7:0] unaffected = overflow_cpu.u_DMEM.memory[8'hAB];
    wire [1:0] illegal_cause = illegal_cpu.exception_cause;
    wire [7:0] illegal_epc = illegal_cpu.exception_epc;
    wire [7:0] error_marker = illegal_cpu.u_DMEM.memory[8'hFF];
    wire [7:0] blocked_store = illegal_cpu.u_DMEM.memory[8'hBB];
    wire [1:0] trap_cause = trap_cpu.exception_cause;
    wire [7:0] trap_epc = trap_cpu.exception_epc;
    wire [7:0] saved_epc = trap_cpu.u_DMEM.memory[8'hDD];
    wire [7:0] blocked_trap_store = trap_cpu.u_DMEM.memory[8'hCC];
    wire [7:0] register1 = overflow_cpu.u_RegFile.registers[1];
    wire [7:0] register2 = overflow_cpu.u_RegFile.registers[2];
    wire [7:0] register3 = overflow_cpu.u_RegFile.registers[3];
    wire [7:0] register4 = overflow_cpu.u_RegFile.registers[4];

    initial begin
        $dumpfile("sim/bonus2/bonus2_exceptions.vcd");
        $dumpvars(0, clk, rst, overflow_pc, overflow_cause, overflow_epc, clamped, unaffected,
                  illegal_cause, illegal_epc, error_marker, blocked_store,
                  trap_cause, trap_epc, saved_epc, blocked_trap_store, register1, register2, register3, register4);
        #1;
        $readmemh("sim/bonus2/bonus_overflow.hex", overflow_cpu.u_IMEM.memory);
        $readmemh("sim/bonus2/bonus_illegal.hex", illegal_cpu.u_IMEM.memory);
        $readmemh("sim/bonus2/bonus_trap.hex", trap_cpu.u_IMEM.memory);
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (150) @(posedge clk);
        if (!overflow_cpu.ID_EX_halt || overflow_cause !== 1 || overflow_epc !== 2 || clamped !== 8'hFF || unaffected !== 100)
            $fatal(1, "Overflow exception test failed");
        if (!illegal_cpu.ID_EX_halt || illegal_cause !== 2 || illegal_epc !== 2 || error_marker !== 8'hEE || blocked_store !== 0)
            $fatal(1, "Illegal instruction test failed");
        if (!trap_cpu.ID_EX_halt || trap_cause !== 3 || trap_epc !== 1 || saved_epc !== 1 || blocked_trap_store !== 0)
            $fatal(1, "TRAP exception test failed");
        $display("PASS Bonus 2: overflow, illegal instruction, and TRAP verified");
        $finish;
    end
endmodule
