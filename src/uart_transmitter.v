`timescale 1ns / 1ps

module UART_Transmitter #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer CLOCKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       write_strobe,
    input  wire [7:0] data_in,
    output reg        tx,
    output wire       ready
);
    localparam integer COUNTER_W = (CLOCKS_PER_BIT <= 1) ? 1 : $clog2(CLOCKS_PER_BIT);
    localparam [1:0] TX_IDLE = 2'd0, TX_START = 2'd1, TX_DATA = 2'd2, TX_STOP = 2'd3;

    reg [1:0] state;
    reg [COUNTER_W-1:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] shift_data;
    reg busy;

    assign ready = !busy;

    always @(posedge clk) begin
        if (rst) begin
            state      <= TX_IDLE;
            baud_count <= {COUNTER_W{1'b0}};
            bit_index  <= 3'd0;
            shift_data <= 8'd0;
            busy       <= 1'b0;
            tx         <= 1'b1;
        end else if (!busy) begin
            tx <= 1'b1;
            if (write_strobe) begin
                shift_data <= data_in;
                baud_count <= {COUNTER_W{1'b0}};
                bit_index  <= 3'd0;
                state      <= TX_START;
                busy       <= 1'b1;
                tx         <= 1'b0;
            end
        end else if (baud_count == CLOCKS_PER_BIT - 1) begin
            baud_count <= {COUNTER_W{1'b0}};
            case (state)
                TX_START: begin
                    state <= TX_DATA;
                    tx    <= shift_data[0];
                end
                TX_DATA: begin
                    if (bit_index == 3'd7) begin
                        state <= TX_STOP;
                        tx    <= 1'b1;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        tx        <= shift_data[bit_index + 1'b1];
                    end
                end
                default: begin
                    state <= TX_IDLE;
                    busy  <= 1'b0;
                    tx    <= 1'b1;
                end
            endcase
        end else begin
            baud_count <= baud_count + 1'b1;
        end
    end
endmodule
