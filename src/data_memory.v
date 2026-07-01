`timescale 1ns / 1ps

module DataMemory (
    input  wire       clk,
    input  wire       we,
    input  wire [7:0] addr,
    input  wire [7:0] wd,
    output wire [7:0] rd,
    output reg  [7:0] pwm_duty_cycle
);
    reg [7:0] memory [0:254];

    assign rd = (addr == 8'hFF) ? 8'h00 : memory[addr];

    always @(posedge clk) begin
        if (we) begin
            if (addr == 8'hFF) pwm_duty_cycle <= wd;
            else               memory[addr] <= wd;
        end
    end
endmodule
