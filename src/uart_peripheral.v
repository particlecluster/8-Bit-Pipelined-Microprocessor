`timescale 1ns / 1ps

module UART_Peripheral #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output wire       tx,
    input  wire       tx_write,
    input  wire [7:0] tx_data,
    input  wire       rx_read,
    output wire [7:0] rx_data,
    output wire [7:0] status
);
    wire tx_ready;
    wire rx_valid;
    wire rx_overrun;

    UART_Transmitter #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)
    ) u_TX (
        .clk(clk), .rst(rst), .write_strobe(tx_write), .data_in(tx_data),
        .tx(tx), .ready(tx_ready)
    );

    UART_Receiver #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)
    ) u_RX (
        .clk(clk), .rst(rst), .rx(rx), .read_strobe(rx_read),
        .data_out(rx_data), .valid(rx_valid), .overrun(rx_overrun)
    );

    assign status = {rx_overrun, 5'b00000, tx_ready, rx_valid};
endmodule
