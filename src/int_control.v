`timescale 1ns / 1ps

module InterruptController #(
    parameter integer ADDR_W = 8
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               interrupt_pin,
    input  wire               reti_taken,
    input  wire               ex_mispredict,
    input  wire [ADDR_W-1:0]  ex_recovery_pc,
    input  wire [ADDR_W-1:0]  IF_ID_pc,
    output wire               trigger_int,
    output reg  [ADDR_W-1:0]  epc
);
    reg int_d;   
    reg in_isr;  

    always @(posedge clk) begin
        if (rst) int_d <= 1'b0;
        else     int_d <= interrupt_pin;
    end
    
    wire int_edge = interrupt_pin & ~int_d; 
    assign trigger_int = int_edge & ~in_isr & ~rst; 

    always @(posedge clk) begin
        if (rst) begin
            in_isr <= 1'b0;
            epc    <= {ADDR_W{1'b0}};
        end else if (trigger_int) begin
            in_isr <= 1'b1;
            epc    <= (ex_mispredict) ? ex_recovery_pc : IF_ID_pc; 
        end else if (reti_taken) begin
            in_isr <= 1'b0;
        end
    end
endmodule
