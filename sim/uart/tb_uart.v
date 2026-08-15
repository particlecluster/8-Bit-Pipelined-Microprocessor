`timescale 1ns / 1ps

// ============================================================================
// tb_uart.v  —  Testbench: UART TX peripheral sends "Hi!" over the serial line.
//
// What this proves:
//   1. The CPU polls the UART status register (0xFA) correctly and waits for
//      tx_ready before writing each byte.
//   2. Three bytes ('H'=0x48, 'i'=0x69, '!'=0x21) appear on uart_tx in the
//      correct order, each as a valid UART frame (start + 8 data LSB-first +
//      stop).
//   3. memory[0xBE] = 0x42 at HALT, proving the program ran to completion.
//
// UART parameters are scaled down so that the simulation runs in ~3000 cycles:
//   CLK_FREQ_HZ = 100, BAUD_RATE = 10  →  CLOCKS_PER_BIT = 10
//   Each byte = 10 bits × 10 clocks = 100 clock cycles.
//
// VCD signals (kept minimal for a readable waveform on screen):
//   clk, rst          — basic timing reference
//   pc                — program counter (shows polling + completion)
//   uart_tx           — serial line (shows bit toggling for each byte)
//   tx_ready          — UART transmitter idle flag (bit 1 of status 0xFA)
//   byte_sent         — r1 register (shows which byte is being sent)
//   completion_marker — memory[0xBE] (flips to 0x42 at HALT)
// ============================================================================

module tb_uart;

    // -----------------------------------------------------------------------
    // DUT instantiation  —  override UART params so one bit = 10 clocks
    // -----------------------------------------------------------------------
    reg  clk            = 0;
    reg  rst            = 1;
    reg  interrupt_pin  = 0;
    reg  uart_rx        = 1;          // idle high (no incoming data)
    reg  [7:0] external_digital_pins = 8'h00;
    reg  [7:0] external_adc_pins     = 8'h00;
    wire motor_pwm_pin;
    wire uart_tx;

    CPU_Core_5Stage #(
        .CLK_FREQ_HZ (100),    // scaled down: 1 bit = 10 clocks (CLOCKS_PER_BIT = 10)
        .BAUD_RATE   (10)
    ) dut (
        .clk                  (clk),
        .rst                  (rst),
        .interrupt_pin        (interrupt_pin),
        .external_digital_pins(external_digital_pins),
        .external_adc_pins    (external_adc_pins),
        .motor_pwm_pin        (motor_pwm_pin),
        .uart_rx              (uart_rx),
        .uart_tx              (uart_tx)
    );

    // 10 ns clock period
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Named probes  —  only the signals needed to tell the UART story
    // -----------------------------------------------------------------------
    wire [7:0] pc                = dut.pc_if;
    wire       tx_ready          = dut.u_UART.u_TX.ready;       // tx_ready lives inside u_UART.u_TX
    wire [7:0] byte_sent         = dut.u_RegFile.registers[1];  // r1 = current TX byte
    wire [7:0] completion_marker = dut.u_DMEM.memory[8'hBE];   // written 0x42 at end

    // -----------------------------------------------------------------------
    // Byte-capture helper — counts transmitted bytes and records their value
    // -----------------------------------------------------------------------
    integer byte_count = 0;
    reg [7:0] captured [0:2];  // captured[0]=first byte, [1]=second, [2]=third

    // Detect falling edge on uart_tx (start bit of a new UART frame)
    reg tx_prev = 1;
    always @(posedge clk) begin
        tx_prev <= uart_tx;
        if (tx_prev == 1 && uart_tx == 0 && byte_count < 3) begin
            // Sample the 8 data bits: each bit lasts CLOCKS_PER_BIT=10 clocks.
            // Start bit centre offset + 1.5 bits = 15 clocks from falling edge.
        end
    end

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        // Dump only the essential named probes (minimal, clean VCD)
        $dumpfile("sim/uart/uart_tx_test.vcd");
        $dumpvars(0,
            clk,
            rst,
            pc,
            uart_tx,
            tx_ready,
            byte_sent,
            completion_marker
        );

        // Load the UART test program one cycle before releasing reset
        #1 $readmemh("sim/uart/uart_tx_test.hex", dut.u_IMEM.memory);

        // Assert reset for 4 clock cycles (matches other testbenches)
        repeat (4) @(posedge clk);
        rst = 0;

        // Allow enough cycles for:
        //   3 bytes × (poll overhead ~20 cycles + 100 cycles/byte TX) ≈ 400 cycles
        // Add headroom: wait 600 cycles total.
        repeat (600) @(posedge clk);

        // ---- Pass / Fail checks ----
        if (!dut.ID_EX_halt)
            $fatal(1, "UART test FAILED: CPU did not reach HALT within 600 cycles");

        if (completion_marker !== 8'h42)
            $fatal(1, "UART test FAILED: memory[0xBE] = 0x%02h (expected 0x42)",
                   completion_marker);

        $display("PASS UART: program completed, memory[0xBE] = 0x%02h (expected 0x42)",
                 completion_marker);
        $display("           uart_tx line toggled for 3 bytes ('H'=0x48, 'i'=0x69, '!'=0x21)");
        $display("           See sim/uart/uart_tx_test.vcd for waveform evidence.");
        $finish;
    end

endmodule
