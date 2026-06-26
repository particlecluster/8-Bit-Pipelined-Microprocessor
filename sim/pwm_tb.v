`timescale 1ns / 1ps

module CPU_Core_tb;

    // --- 1. Global Simulation Inputs/Outputs ---
    reg clk;
    reg rst;
    wire motor_pwm_pin;

    // --- 2. Instantiate Your CPU Core (UUT) ---
    CPU_Core uut (
        .clk(clk),
        .rst(rst),
        .motor_pwm_pin(motor_pwm_pin)
    );

    // --- 3. Clock Generation (100MHz Clock -> 10ns Period) ---
    always begin
        #5 clk = ~clk; // Toggle every 5ns
    end

    // --- 4. Simulation Control Block ---
    initial begin
        // Step A: Initialize signals and hold CPU in reset
        clk = 0;
        rst = 1; 
        #20;     // Wait 2 cycles
        
        // Step B: Release reset to let the program start running
        rst = 0; 
        
        // Step C: Run the simulation long enough to see execution steps
        #3000;
        
        // Optional Step D: Gracefully terminate the simulation run
        $display("-----------------------------------------");
        $display("[TB INFO] Simulation Finished Successfully.");
        $display("-----------------------------------------");
        $finish;
    end

    // --- 5. Real-Time Waveform Tracking Console ---
    initial begin
        $monitor("Time = %0t ns | PC = 0x%h | Instr = 0x%h | PWM Out = %b", 
                 $time, uut.pc, uut.instr, motor_pwm_pin);
    end

endmodule
