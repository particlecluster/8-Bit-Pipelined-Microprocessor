`timescale 1ns / 1ps

module ResetSynchronizer (
    input  wire clk,
    input  wire async_rst_in,
    output reg  sync_rst_out
);
    reg rst_ff1;

    always @(posedge clk or posedge async_rst_in) begin
        if (async_rst_in) begin
            rst_ff1      <= 1'b1;
            sync_rst_out <= 1'b1;
        end else begin
            rst_ff1      <= 1'b0;
            sync_rst_out <= rst_ff1;
        end
    end
endmodule
