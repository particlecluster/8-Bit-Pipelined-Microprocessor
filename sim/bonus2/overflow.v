`timescale 1ns / 1ps
module tb_bonus2;
    reg clk = 0, rst = 1, interrupt_pin = 0, uart_rx = 1;
    reg [7:0] external_digital_pins = 0, external_adc_pins = 0;
    wire pwm0, pwm1, pwm2, tx0, tx1, tx2;
    CPU_Core_5Stage overflow_cpu (.clk(clk), .rst(rst), .interrupt_pin(interrupt_pin), .external_digital_pins(external_digital_pins), .external_adc_pins(external_adc_pins), .motor_pwm_pin(pwm0), .uart_rx(uart_rx), .uart_tx(tx0));
  
    always #5 clk = ~clk;

    wire [7:0] overflow_pc = overflow_cpu.pc_if;
    wire [1:0] overflow_cause = overflow_cpu.exception_cause;
    wire [7:0] overflow_epc = overflow_cpu.exception_epc;
    wire [7:0] clamped = overflow_cpu.u_DMEM.memory[8'hAA];
    wire [7:0] unaffected = overflow_cpu.u_DMEM.memory[8'hAB];

    wire [7:0] register1 = overflow_cpu.u_RegFile.registers[1];
    wire [7:0] register2 = overflow_cpu.u_RegFile.registers[2];
    wire [7:0] register3 = overflow_cpu.u_RegFile.registers[3];
    wire [7:0] register4 = overflow_cpu.u_RegFile.registers[4];


    initial begin
        $dumpfile("sim/bonus2/overflow.vcd");
        $dumpvars(0, clk, rst, overflow_pc, overflow_cause, overflow_epc, clamped, unaffected, register1, register2, register3, register4);
        #1;
        $readmemh("sim/bonus2/bonus_overflow.hex", overflow_cpu.u_IMEM.memory);

        repeat (4) @(posedge clk);
        rst = 0;
        repeat (150) @(posedge clk);
        if (!overflow_cpu.ID_EX_halt || overflow_cause !== 1 || overflow_epc !== 2 || clamped !== 8'hFF || unaffected !== 100)
            $fatal(1, "Overflow exception test failed");
        
        $display("PASS Bonus 2: overflow verified");
        $finish;
    end
endmodule
