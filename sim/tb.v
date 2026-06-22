`timescale 1ns / 1ps

module tb_cpu_hex;

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
        // 1. Setup Waveform Dumping (For GTKWave)
        $dumpfile("cpu.vcd");
        $dumpvars(0, tb_cpu_hex);

        // 2. Initialize clock and reset
        clk = 0;
        rst = 1;

        // 3. Load the hex file from the Web Assembler
        $readmemh("program.hex", uut.u_IMEM.memory);
        $display("Loaded program.hex into Instruction Memory.");

        // 4. Release reset to start execution
        #20;
        rst = 0;

        // 5. Let the CPU run long enough to finish the sorting loop
        #10000; 

        // 6. Verify Results Automatically
        $display("=======================================");
        $display("        SORTING ALGORITHM RESULTS      ");
        $display("=======================================");
        $display("arr[0] = %0d (Expected: 2)", uut.u_DMEM.memory[10]);
        $display("arr[1] = %0d (Expected: 5)", uut.u_DMEM.memory[11]);
        $display("arr[2] = %0d (Expected: 8)", uut.u_DMEM.memory[12]);
        $display("=======================================");

        // 7. End simulation
        $finish;
    end

endmodule
