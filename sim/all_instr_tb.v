`timescale 1ns / 1ps

module tb_cpu_all_instr;

    // --- Signals ---
    reg clk;
    reg rst;
    wire motor_pwm_pin;

    // --- CPU Instantiation ---
    CPU_Core uut (
        .clk(clk), 
        .rst(rst), 
        .motor_pwm_pin(motor_pwm_pin)
    );

    // --- Clock Generation ---
    always #5 clk = ~clk; // 10ns period

    initial begin
        $dumpfile("cpu_test.vcd");
        $dumpvars(0, tb_cpu_all_instr);

        // Initialize clock and reset
        clk = 0;
        rst = 1;

        $display("Loading program.hex...");
        // Wait for system reset synchronizer to clear
        #20;
        rst = 0;

        // Run long enough to finish all 48 instructions
        #1000; 

        // Verify Results Automatically
        $display("=======================================");
        $display("      ISA EVALUATION RESULTS           ");
        $display("=======================================");
        $display("MEM[0]  (ADD)  = %0d \t(Expected: 13)", uut.u_DMEM.memory[0]);
        $display("MEM[1]  (SUB)  = %0d \t(Expected: 7)",  uut.u_DMEM.memory[1]);
        $display("MEM[2]  (AND)  = %0d \t(Expected: 2)",  uut.u_DMEM.memory[2]);
        $display("MEM[3]  (ORR)  = %0d \t(Expected: 11)", uut.u_DMEM.memory[3]);
        $display("MEM[4]  (XOR)  = %0d \t(Expected: 9)",  uut.u_DMEM.memory[4]);
        $display("MEM[5]  (SHL)  = %0d \t(Expected: 80)", uut.u_DMEM.memory[5]);
        $display("MEM[6]  (SHR)  = %0d \t(Expected: 1)",  uut.u_DMEM.memory[6]);
        $display("MEM[7]  (SLT)  = %0d \t(Expected: 0)",  uut.u_DMEM.memory[7]);
        $display("MEM[8]  (MUL)  = %0d \t(Expected: 30)", uut.u_DMEM.memory[8]);
        $display("MEM[9]  (MAC)  = %0d \t(Expected: 35)", uut.u_DMEM.memory[9]);
        $display("MEM[10] (ROL)  = %0d \t(Expected: 80)", uut.u_DMEM.memory[10]);
        $display("MEM[11] (ROR)  = %0d \t(Expected: 65)", uut.u_DMEM.memory[11]);
        $display("MEM[12] (ADDI) = %0d \t(Expected: 14)", uut.u_DMEM.memory[12]);
        $display("MEM[13] (LOAD) = %0d \t(Expected: 13)", uut.u_DMEM.memory[13]);
        $display("MEM[14] (BEQ)  = %0d \t(Expected: 88)", uut.u_DMEM.memory[14]);
        $display("MEM[15] (BNE)  = %0d \t(Expected: 77)", uut.u_DMEM.memory[15]);
        $display("MEM[16] (BGT)  = %0d \t(Expected: 66)", uut.u_DMEM.memory[16]);
        $display("MEM[17] (JMP)  = %0d \t(Expected: 55)", uut.u_DMEM.memory[17]);
        $display("=======================================");

        $finish;
    end

endmodule
