`timescale 1ns / 1ps

module PWM_Generator #(
    parameter integer DATA_W = 8
) (
    input  wire              clk,
    input  wire              rst,
    input  wire [DATA_W-1:0] duty_cycle,
    output reg               pwm_out
);
    reg [DATA_W-1:0] counter;
    
    always @(posedge clk) begin
        if (rst) begin
            counter <= {DATA_W{1'b0}}; 
            pwm_out <= 1'b0;
        end else begin
            counter <= counter + 1'b1;
            pwm_out <= (counter < duty_cycle) ? 1'b1 : 1'b0;
        end
    end
endmodule
