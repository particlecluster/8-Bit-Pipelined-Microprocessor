`timescale 1ns / 1ps

module tb_fact;
    reg clk = 0;
    reg rst = 1;
    reg interrupt_pin = 0;
    reg uart_rx = 1;
    reg [7:0] external_digital_pins = 0;
    reg [7:0] external_adc_pins = 0;
    wire pwm_motor, uart_tx;

    // CPU Instantiation
    CPU_Core_5Stage dut (
        .clk(clk),
        .rst(rst),
        .interrupt_pin(interrupt_pin),
        .external_digital_pins(external_digital_pins),
        .external_adc_pins(external_adc_pins),
        .motor_pwm_pin(pwm_motor),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    // Clock Generation
    always #5 clk = ~clk;

    // Probes for VCD visibility
    wire [7:0] pc = dut.pc_if;
    wire [7:0] sp = dut.u_RegFile.registers[6]; // Stack Pointer (R6)
    wire [7:0] ra = dut.u_RegFile.registers[7]; // Return Address (R7)
    wire [7:0] n  = dut.u_RegFile.registers[1]; // Argument/Result (R1)
    wire [7:0] final_result = dut.u_DMEM.memory[8'hA0]; // Result memory location
    
    // Probes for the stack memory
    wire [7:0] stack_top = dut.u_DMEM.memory[8'h70];
    wire [7:0] stack_mid = dut.u_DMEM.memory[8'h6E];

    initial begin
        // Setup waveform dumping
        $dumpfile("sim/fact/fact.vcd");
        $dumpvars(0, tb_fact);
        
        #1;
        // Load the hex file
        $readmemh("sim/fact/fact.hex", dut.u_IMEM.memory);
        
        // Reset sequence
        repeat(4) @(posedge clk);
        rst = 0;

        // Run until HALT or timeout (factorial 5 should take around 150 cycles)
        repeat (300) begin
            @(posedge clk);
            if (!rst)
                $display("Cycle %0d: PC=%02h, R1(n)=%02h, R6(SP)=%02h, R7(RA)=%02h", $time/10, pc, n, sp, ra);
            
            if (dut.ID_EX_halt) begin
                #1; // Let non-blocking memory writes settle!
                $display("\n=====================================");
                $display("HALT instruction reached at cycle %0d", $time/10);
                $display("Checking final result at memory[0xA0]...");
                
                if (final_result === 8'h78) begin
                    $display("SUCCESS: memory[0xA0] = 0x%h (120)", final_result);
                    $display("Recursive Factorial verified perfectly!");
                end else begin
                    $display("FAIL: Expected 0x78, got 0x%h", final_result);
                end
                
                $display("=====================================\n");
                $finish;
            end
        end

        // Timeout fallback
        $display("FATAL: Simulation timeout after 300 cycles! CPU did not reach HALT.");
        $finish;
    end
endmodule
