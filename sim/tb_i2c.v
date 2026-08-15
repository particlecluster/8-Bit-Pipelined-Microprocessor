`timescale 1ns / 1ps

module tb_i2c;

    // Signals
    reg clk;
    reg rst;
    reg cmd_write;
    reg [4:0] cmd_reg;
    reg [7:0] data_in;
    wire [7:0] data_out;
    wire [2:0] status_reg;
    
    wire scl;
    wire sda;
    
    // Bidirectional lines interface
    wire scl_oe, sda_oe;
    wire scl_in, sda_in;
    
    assign scl = scl_oe ? 1'b0 : 1'bz;
    assign scl_in = scl;
    assign sda = sda_oe ? 1'b0 : 1'bz;
    assign sda_in = sda;
    
    // Pull-ups on I2C lines
    pullup(scl);
    pullup(sda);

    // Instantiate Master
    I2C_Peripheral #(
        .SYS_CLK_FREQ(25_000_000),
        .I2C_CLK_FREQ(100_000)
    ) u_master (
        .clk(clk),
        .rst(rst),
        .cmd_write(cmd_write),
        .cmd_reg(cmd_reg),
        .data_in(data_in),
        .data_out(data_out),
        .status_reg(status_reg),
        .scl_in(scl_in),
        .scl_oe(scl_oe),
        .sda_in(sda_in),
        .sda_oe(sda_oe)
    );

    // Mock I2C Slave (Responds to address 0x68 / 8'hD0 and 8'hD1)
    // Simply pulls SDA low during the 9th bit clock of the address and data byte phase.
    reg slave_ack_oe;
    assign sda = slave_ack_oe ? 1'b0 : 1'bz;
    
    integer bit_idx;
    
    initial begin
        slave_ack_oe = 0;
        forever begin
            // Wait for START condition (SDA falling while SCL is high)
            @(negedge sda);
            if (scl == 1'b1) begin
                $display("[Slave] START detected");
                
                // Read 8 address bits
                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    @(posedge scl);
                end
                
                // 9th clock is ACK
                @(negedge scl);
                #100; // Small delay
                slave_ack_oe = 1'b1; // Send ACK
                $display("[Slave] Sending ACK for address");
                
                @(negedge scl);
                #100;
                slave_ack_oe = 1'b0; // Release
                
                // Read 8 data bits (if write transaction)
                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    @(posedge scl);
                end
                
                // 9th clock is ACK
                @(negedge scl);
                #100;
                slave_ack_oe = 1'b1; // Send ACK
                $display("[Slave] Sending ACK for data byte");
                
                @(negedge scl);
                #100;
                slave_ack_oe = 1'b0; // Release
            end
        end
    end

    // Clock generation (25 MHz -> 40ns period)
    always #20 clk = ~clk;

    initial begin
        // Initialize
        clk = 0;
        rst = 1;
        cmd_write = 0;
        cmd_reg = 0;
        data_in = 0;
        
        // Dump waves
        $dumpfile("i2c_sim.vcd");
        $dumpvars(0, tb_i2c);

        #100;
        rst = 0;
        #100;

        $display("--- Starting I2C Write Transaction ---");
        
        // 1. Issue START + WRITE of address 0xD0 (MPU6050 address 0x68 + Write bit 0)
        @(posedge clk);
        cmd_reg = 5'b00101; // [0]:START, [2]:WRITE
        data_in = 8'hD0;
        cmd_write = 1;
        @(posedge clk);
        cmd_write = 0;
        
        // Wait for busy to clear
        @(negedge status_reg[0]); // Negedge of Busy
        $display("[Master] Write Address done. Ack received (0=ACK, 1=NACK): %b", status_reg[1]);

        #1000;

        // 2. Issue WRITE of data 0x75 (Register address for WHO_AM_I)
        @(posedge clk);
        cmd_reg = 5'b00100; // [2]:WRITE
        data_in = 8'h75;
        cmd_write = 1;
        @(posedge clk);
        cmd_write = 0;
        
        // Wait for busy to clear
        @(negedge status_reg[0]);
        $display("[Master] Write Data done. Ack received: %b", status_reg[1]);

        #1000;

        // 3. Issue STOP condition
        @(posedge clk);
        cmd_reg = 5'b00010; // [1]:STOP
        cmd_write = 1;
        @(posedge clk);
        cmd_write = 0;

        // Wait for busy to clear
        @(negedge status_reg[0]);
        $display("[Master] STOP done.");

        #5000;
        $display("--- Simulation Finished ---");
        $finish;
    end

endmodule
