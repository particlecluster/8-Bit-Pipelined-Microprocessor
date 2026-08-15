`timescale 1ns / 1ps
module tb_bonus2;
    reg clk = 0, rst = 1, interrupt_pin = 0, uart_rx = 1;
    reg [7:0] external_digital_pins = 0, external_adc_pins = 0;
    wire pwm0, pwm1, pwm2, tx0, tx1, tx2;
    CPU_Core_5Stage illegal_cpu  (.clk(clk), .rst(rst), .interrupt_pin(interrupt_pin), .external_digital_pins(external_digital_pins), .external_adc_pins(external_adc_pins), .motor_pwm_pin(pwm1), .uart_rx(uart_rx), .uart_tx(tx1));
    always #5 clk = ~clk;

    wire [1:0] illegal_cause = illegal_cpu.exception_cause;
    wire [7:0] illegal_epc = illegal_cpu.exception_epc;
    wire [7:0] error_marker = illegal_cpu.u_DMEM.memory[8'hFF];
    wire [7:0] blocked_store = illegal_cpu.u_DMEM.memory[8'hBB];
    wire [7:0] illegal_pc = illegal_cpu.pc_if;

    wire [7:0] register1 = illegal_cpu.u_RegFile.registers[1];
    wire [7:0] register2 = illegal_cpu.u_RegFile.registers[2];
    wire [7:0] register3 = illegal_cpu.u_RegFile.registers[3];
    wire [7:0] register4 = illegal_cpu.u_RegFile.registers[4];

    initial begin
        $dumpfile("sim/bonus2/illegal.vcd");
        $dumpvars(0, clk, rst, illegal_pc,
                  illegal_cause, illegal_epc, error_marker, blocked_store,
                   register1, register2, register3, register4);
        #1;
        $readmemh("sim/bonus2/bonus_illegal.hex", illegal_cpu.u_IMEM.memory);
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (150) @(posedge clk);
        if (!illegal_cpu.ID_EX_halt || illegal_cause !== 2 || illegal_epc !== 2 || error_marker !== 8'hEE || blocked_store !== 0)
            $fatal(1, "Illegal instruction test failed");
        
        $display("PASS Bonus 2: overflow, illegal instruction, and TRAP verified");
        $finish;
    end
endmodule
