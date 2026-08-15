`timescale 1ns / 1ps

module DataMemory_UART #(
    parameter integer DATA_W = 8,
    parameter integer ADDR_W = 8
) (
    input  wire              clk,
    input  wire              we,
    input  wire [ADDR_W-1:0] addr,
    input  wire [DATA_W-1:0] wd,
    output wire [DATA_W-1:0] rd,
    input  wire [DATA_W-1:0] digital_in,
    input  wire [DATA_W-1:0] adc_in,
    input  wire [DATA_W-1:0] uart_rx_data,
    input  wire [DATA_W-1:0] uart_status,
    output reg  [DATA_W-1:0] pwm_duty_cycle,
    input  wire [DATA_W-1:0] i2c_data_in,
    input  wire [DATA_W-1:0] i2c_status_in,
    output reg  [DATA_W-1:0] accel_x,      // Accelerometer X data (signed 8-bit from MPU6050)
    output reg  [DATA_W-1:0] accel_y       // Accelerometer Y data (signed 8-bit from MPU6050)
);
    reg [DATA_W-1:0] memory [0:(1<<ADDR_W)-1];
    integer i;

    initial begin
        pwm_duty_cycle = {DATA_W{1'b0}};
        accel_x = 8'h00;
        accel_y = 8'h00;
        
        for (i = 0; i < (1<<ADDR_W); i = i + 1)
            memory[i] = {DATA_W{1'b0}};
    end

    assign rd = (addr == 8'hFF) ? pwm_duty_cycle : 
                (addr == 8'hFE) ? digital_in : 
                (addr == 8'hFD) ? adc_in :
                (addr == 8'hFA) ? uart_status :
                (addr == 8'hFB) ? uart_rx_data :
                (addr == 8'hF8) ? i2c_data_in :  // NEW
                (addr == 8'hF7) ? i2c_status_in :// NEW
                (addr == 8'hF4) ? accel_x :      // NEW
                (addr == 8'hF3) ? accel_y :      // NEW
                memory[addr];

    always @(posedge clk) begin
        if (we) begin       
            if (addr == 8'hFF) begin
                pwm_duty_cycle <= wd;
                memory[addr] <= wd;
            end
            else if (addr == 8'hF4) begin  // accel_x written by CPU I2C program
                accel_x <= wd;
                memory[addr] <= wd;
            end
            else if (addr == 8'hF3) begin  // accel_y written by CPU I2C program
                accel_y <= wd;
                memory[addr] <= wd;
            end
            else if (addr != 8'hFE && addr != 8'hFD && addr != 8'hFA &&
                     addr != 8'hFB && addr != 8'hFC &&
                     addr != 8'hF8 && addr != 8'hF7 && addr != 8'hF4 &&
                     addr != 8'hF3) memory[addr] <= wd; 
        end
    end
endmodule
