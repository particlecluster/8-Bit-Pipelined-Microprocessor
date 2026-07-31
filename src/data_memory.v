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
    output reg  [DATA_W-1:0] pwm_duty_cycle
);
    reg [DATA_W-1:0] memory [0:(1<<ADDR_W)-1];
    
    initial begin
        pwm_duty_cycle = {DATA_W{1'b0}};
    end

    // UART map: 0xFA = {rx_overrun, 5'b0, tx_ready, rx_valid},
    //           0xFB = received byte, 0xFC = transmit-data write register.
    assign rd = (addr == 8'hFF) ? pwm_duty_cycle : 
                (addr == 8'hFE) ? digital_in : 
                (addr == 8'hFD) ? adc_in :
                (addr == 8'hFA) ? uart_status :
                (addr == 8'hFB) ? uart_rx_data :
                memory[addr];

    always @(posedge clk) begin
        if (we) begin
            if (addr == 8'hFF) pwm_duty_cycle <= wd;
            else if (addr != 8'hFE && addr != 8'hFD && addr != 8'hFA &&
                     addr != 8'hFB && addr != 8'hFC) memory[addr] <= wd; 
        end
    end
endmodule
