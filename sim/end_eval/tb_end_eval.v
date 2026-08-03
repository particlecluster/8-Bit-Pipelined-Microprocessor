`timescale 1ns / 1ps
module tb_end_eval;
    reg clk = 0, rst = 1, interrupt_pin = 0, uart_rx = 1;
    reg [7:0] external_digital_pins = 0, external_adc_pins = 0;
    wire motor_pwm_pin, uart_tx;
    CPU_Core_5Stage dut (.clk(clk), .rst(rst), .interrupt_pin(interrupt_pin),
        .external_digital_pins(external_digital_pins), .external_adc_pins(external_adc_pins),
        .motor_pwm_pin(motor_pwm_pin), .uart_rx(uart_rx), .uart_tx(uart_tx));
    always #5 clk = ~clk;

    wire [7:0] pc = dut.pc_if;
    wire [4:0] ex_opcode = dut.ID_EX_opcode;
    wire [7:0] r1 = dut.u_RegFile.registers[1];
    wire [7:0] r3 = dut.u_RegFile.registers[3];
    wire [7:0] r5 = dut.u_RegFile.registers[5];
    wire [7:0] r6 = dut.u_RegFile.registers[6];
    wire [7:0] shifted_result = dut.u_DMEM.memory[8'h6C];
    wire [7:0] r5_saved = dut.u_DMEM.memory[8'h70];
    wire [7:0] r7_saved = dut.u_DMEM.memory[8'h74];

    initial begin
        $dumpfile("sim/end_eval/end_eval.vcd");
        $dumpvars(0, clk, rst, pc, ex_opcode, r1, r3, r5, r6,
                  shifted_result, r5_saved, r7_saved);
        #1 $readmemh("sim/end_eval/end_eval.hex", dut.u_IMEM.memory);
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (180) @(posedge clk);
        if (!dut.ID_EX_halt || r1 !== 50 || r3 !== 25 || r5 !== 48 || r6 !== 21 ||
            r5_saved !== 23 || r7_saved !== 33 || shifted_result !== 132)
            $fatal(1, "End-evaluation program failed");
        $display("PASS End Eval: R1=50 R3=25 R5=48 R6=21 R7(saved)=33 shifted=132");
        $finish;
    end
endmodule
