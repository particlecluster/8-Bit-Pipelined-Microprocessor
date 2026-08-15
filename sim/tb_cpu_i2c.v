`timescale 1ns / 1ps

module tb_cpu_i2c;

    // Ports
    reg clk_100mhz;
    reg rst;
    wire [3:0] led_out;
    wire i2c_sda;
    wire i2c_scl;

    // Pull-ups on I2C lines
    pullup(i2c_scl);
    pullup(i2c_sda);
    
    wire [7:0] matrix_rows;
    wire [7:0] matrix_cols;

    // Instantiate CPU (matches your updated top module port list)
    CPU_Core_5Stage dut (
        .clk_100mhz(clk_100mhz),
        .rst(rst),
        .led_out(led_out),
        .i2c_sda(i2c_sda),
        .i2c_scl(i2c_scl),
        .matrix_rows(matrix_rows),
        .matrix_cols(matrix_cols)
    );

    // Clock Gen: 100 MHz (10ns period)
    initial begin
        clk_100mhz = 0;
        forever #5 clk_100mhz = ~clk_100mhz;
    end

    // Probes for debug
    wire [7:0] pc = dut.pc_if;
    wire [7:0] r1 = dut.u_RegFile.registers[1];
    wire [7:0] r2 = dut.u_RegFile.registers[2];
    wire [7:0] r3 = dut.u_RegFile.registers[3];
    wire [7:0] r4 = dut.u_RegFile.registers[4];
    wire [7:0] r7 = dut.u_RegFile.registers[7];

    // Mock I2C Slave Model (Responds to 7-bit Address 0x68)
    reg slave_ack_oe;
    // We drive 0 to pull line low (open drain), float high otherwise
    assign i2c_sda = slave_ack_oe ? 1'b0 : 1'bz;
    
    integer bit_idx;
    reg [7:0] rx_byte;
    reg is_read;
    reg [7:0] data_to_send;

    initial begin
        slave_ack_oe = 0;
        data_to_send = 8'h68; // WHO_AM_I default register value for MPU6050
        
        forever begin
            // Wait for START condition (SDA drops while SCL is high)
            @(negedge i2c_sda);
            if (i2c_scl == 1'b1) begin
                $display("[Sim Slave] START condition detected.");
                
                // 1. Read 8 bits (Device address + R/W)
                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    @(posedge i2c_scl);
                    rx_byte[7-bit_idx] = i2c_sda;
                end
                is_read = rx_byte[0];
                $display("[Sim Slave] Received Dev Address: 7'h%h, R/W: %b", rx_byte[7:1], is_read);
                
                // 2. Drive ACK on 9th clock
                @(negedge i2c_scl);
                slave_ack_oe = 1; // Pull SDA low for ACK
                @(negedge i2c_scl);
                slave_ack_oe = 0; // Release SDA
                
                if (is_read) begin
                    // --- READ MODE (Slave transmits data_to_send) ---
                    $display("[Sim Slave] Slave transmitting byte: 8'h%h", data_to_send);
                    for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                        slave_ack_oe = ~data_to_send[7-bit_idx];
                        @(negedge i2c_scl);
                    end
                    slave_ack_oe = 0; // Release SDA for master NACK
                    @(negedge i2c_scl); // Wait for end of NACK clock
                end else begin
                    // --- WRITE MODE (Slave receives register address) ---
                    for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                        @(posedge i2c_scl);
                        rx_byte[7-bit_idx] = i2c_sda;
                    end
                    $display("[Sim Slave] Received Register Address: 8'h%h", rx_byte);
                    
                    // Drive ACK on 9th clock
                    @(negedge i2c_scl);
                    slave_ack_oe = 1; // Pull SDA low for ACK
                    @(negedge i2c_scl);
                    slave_ack_oe = 0; // Release SDA
                end
            end
        end
    end

    // Simulation control
    initial begin
        $display("--- Starting Microprocessor CPU I2C Simulation ---");
        $dumpfile("cpu_i2c_sim.vcd");
        $dumpvars(0, tb_cpu_i2c);

        rst = 0; // Reset active (because u_RstSync takes !rst)
        #100;
        @(posedge clk_100mhz);
        rst = 1; // Release reset (rst=1 -> !rst=0)

        #1500000; // Run for 1.5ms to allow both initialization and read phases to complete
        
        $display("--- Simulation Ended ---");
        $display("Final PC: %d", pc);
        $display("Final LED output value: %b (Expected: 1000 if read WHO_AM_I = 8'h68 successfully)", led_out);
        $finish;
    end

endmodule

// Clock Wizard Simulation Stub
module clk_wiz_0 (
    input  wire clk_in1,
    output reg  clk_out1
);
    reg [1:0] counter = 0;
    initial clk_out1 = 0;
    always @(posedge clk_in1) begin
        counter <= counter + 1'b1;
        if (counter == 2'd1) begin
            clk_out1 <= ~clk_out1;
            counter <= 0;
        end
    end
endmodule

