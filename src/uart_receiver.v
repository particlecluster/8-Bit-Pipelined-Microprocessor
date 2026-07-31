`timescale 1ns/ 1ps

module UART_Receiver #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer CLOCKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    input  wire       read_strobe,
    output reg  [7:0] data_out,
    output reg        valid,
    output reg        overrun
);
    localparam integer COUNTER_W = (CLOCKS_PER_BIT <= 1) ? 1 : $clog2(CLOCKS_PER_BIT);
    localparam integer HALF_BIT = (CLOCKS_PER_BIT <= 1) ? 1 : CLOCKS_PER_BIT / 2;
    localparam [1:0] RX_IDLE = 2'd0, RX_START = 2'd1, RX_DATA = 2'd2, RX_STOP = 2'd3;

    reg rx_meta, rx_sync;
    reg [1:0] state;
    reg [COUNTER_W-1:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] shift_data;

    always @(posedge clk) begin
        if (rst) begin
            rx_meta    <= 1'b1;
            rx_sync    <= 1'b1;
            state      <= RX_IDLE;
            baud_count <= {COUNTER_W{1'b0}};
            bit_index  <= 3'd0;
            shift_data <= 8'd0;
            data_out   <= 8'd0;
            valid      <= 1'b0;
            overrun    <= 1'b0;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;

            if (read_strobe) valid <= 1'b0;

            case (state)
                RX_IDLE: if (!rx_sync) begin
                    baud_count <= {COUNTER_W{1'b0}};
                    state <= RX_START;
                end
                RX_START: if (baud_count == HALF_BIT - 1) begin
                    baud_count <= {COUNTER_W{1'b0}};
                    if (!rx_sync) begin
                        bit_index <= 3'd0;
                        // Start was validated at its midpoint. Preload the
                        // counter to sample the first data bit at its midpoint.
                        baud_count <= HALF_BIT;
                        state <= RX_DATA;
                    end else state <= RX_IDLE;
                end else baud_count <= baud_count + 1'b1;
                RX_DATA: if (baud_count == CLOCKS_PER_BIT - 1) begin
                    baud_count <= {COUNTER_W{1'b0}};
                    shift_data[bit_index] <= rx_sync;
                    if (bit_index == 3'd7) state <= RX_STOP;
                    else bit_index <= bit_index + 1'b1;
                end else baud_count <= baud_count + 1'b1;
                default: if (baud_count == CLOCKS_PER_BIT - 1) begin
                    baud_count <= {COUNTER_W{1'b0}};
                    state <= RX_IDLE;
                    if (rx_sync) begin
                        if (valid) overrun <= 1'b1;
                        else begin
                            data_out <= shift_data;
                            valid <= 1'b1;
                        end
                    end
                end else baud_count <= baud_count + 1'b1;
            endcase
        end
    end
endmodule
