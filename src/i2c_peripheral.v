`timescale 1ns / 1ps
`default_nettype none

module I2C_Peripheral #(
    parameter integer SYS_CLK_FREQ = 25_000_000,
    parameter integer I2C_CLK_FREQ = 100_000
) (
    input  wire       clk,
    input  wire       rst,
    
    // Processor register interface
    input  wire       cmd_write,      // Write pulse to 0xF7
    input  wire       data_write,     // Write pulse to 0xF8
    input  wire [4:0] cmd_reg,        // [4]:ACK, [3]:READ, [2]:WRITE, [1]:STOP, [0]:START
    input  wire [7:0] data_in,        // CPU write data bus
    output reg  [7:0] data_out,       // CPU read data bus
    output wire [2:0] status_reg,     // [2]:ERROR, [1]:RX_ACK, [0]:BUSY
    
    // Unidirectional I2C physical lines (to be connected to tristates at top level)
    input  wire       scl_in,
    output reg        scl_oe,         // 1 = pull SCL low, 0 = float SCL high
    input  wire       sda_in,
    output reg        sda_oe          // 1 = pull SDA low, 0 = float SDA high
);

    // Timing parameters: Tick runs at 4x the SCL frequency (400 kHz for 100 kHz SCL)
    localparam integer TICK_DIVIDER = SYS_CLK_FREQ / (I2C_CLK_FREQ * 4);
    
    reg [$clog2(TICK_DIVIDER)-1:0] clk_divider;
    reg i2c_tick;
    
    // Clock stretching detection:
    // If we want SCL high (scl_oe = 0) but the slave is holding SCL low (scl_in = 0), we stall the divider.
    wire scl_stall = 1'b0; // Clock stretching disabled for hardware robustness (prevents hangs)
    
    always @(posedge clk) begin
        if (rst) begin
            clk_divider <= 0;
            i2c_tick <= 1'b0;
        end else begin
            i2c_tick <= 1'b0;
            if (!scl_stall) begin
                if (clk_divider == TICK_DIVIDER - 1) begin
                    clk_divider <= 0;
                    i2c_tick <= 1'b1;
                end else begin
                    clk_divider <= clk_divider + 1'b1;
                end
            end
        end
    end

    // FSM States
    localparam STATE_IDLE        = 4'd0;
    localparam STATE_START_0     = 4'd1;
    localparam STATE_START_1     = 4'd2;
    localparam STATE_SHIFT_TX    = 4'd3;
    localparam STATE_ACK_TX      = 4'd4;
    localparam STATE_SHIFT_RX    = 4'd5;
    localparam STATE_ACK_RX      = 4'd6;
    localparam STATE_STOP_0      = 4'd7;
    localparam STATE_STOP_1      = 4'd8;
    localparam STATE_STOP_2      = 4'd9;

    reg [3:0] state;
    reg [1:0] substate; // Quarter-cycles of a bit (0 to 3)
    reg [2:0] bit_counter;
    
    reg [7:0] i2c_data_reg; // Holds the byte to transmit (written to 0xF8)
    reg [7:0] tx_shift_reg;
    reg [7:0] rx_shift_reg;
    
    reg active_start;
    reg active_stop;
    reg active_write;
    reg active_read;
    reg active_ack;
    
    reg busy;
    reg rx_ack_bit;
    reg error;
    
    assign status_reg = {error, rx_ack_bit, busy};

    always @(posedge clk) begin
        if (rst) begin
            state        <= STATE_IDLE;
            substate     <= 0;
            bit_counter  <= 0;
            scl_oe       <= 1'b0;
            sda_oe       <= 1'b0;
            busy         <= 1'b0;
            rx_ack_bit   <= 1'b0;
            error        <= 1'b0;
            data_out     <= 8'b0;
            i2c_data_reg <= 8'b0;
            tx_shift_reg <= 8'b0;
            rx_shift_reg <= 8'b0;
            active_start <= 1'b0;
            active_stop  <= 1'b0;
            active_write <= 1'b0;
            active_read  <= 1'b0;
            active_ack   <= 1'b0;
        end else begin
            // Latched instantly when writing to data register (0xF8)
            if (data_write) begin
                i2c_data_reg <= data_in;
            end

            // Register writes to command register (0xF7) (latched when not busy)
            if (cmd_write && !busy) begin
                active_start <= cmd_reg[0];
                active_stop  <= cmd_reg[1];
                active_write <= cmd_reg[2];
                active_read  <= cmd_reg[3];
                active_ack   <= cmd_reg[4];
                tx_shift_reg <= i2c_data_reg; // Load shift register from data register
                busy         <= 1'b1;
                error        <= 1'b0;
                
                // Jump immediately into transaction execution
                if (cmd_reg[0]) begin
                    state <= STATE_START_0;
                end else if (cmd_reg[2]) begin
                    state <= STATE_SHIFT_TX;
                    bit_counter <= 3'd7;
                end else if (cmd_reg[3]) begin
                    state <= STATE_SHIFT_RX;
                    bit_counter <= 3'd7;
                end else if (cmd_reg[1]) begin
                    state <= STATE_STOP_0;
                end else begin
                    busy <= 1'b0; // No valid command bit
                end
                substate <= 0;
            end
            
            // FSM Execution at 4x ticks
            else if (busy && i2c_tick) begin
                case (state)
                    // --- START CONDITION ---
                    STATE_START_0: begin
                        // Phase 0: Make sure SDA is released (1) and SCL is released (1)
                        sda_oe <= 1'b0;
                        scl_oe <= 1'b0;
                        state  <= STATE_START_1;
                    end
                    STATE_START_1: begin
                        if (substate == 0) begin
                            sda_oe <= 1'b1; // SDA goes low while SCL is high
                        end else if (substate == 2) begin
                            scl_oe <= 1'b1; // SCL goes low (holds the bus)
                        end
                        
                        if (substate == 3) begin
                            substate <= 0;
                            active_start <= 1'b0;
                            
                            // Check next action after START
                            if (active_write) begin
                                state <= STATE_SHIFT_TX;
                                bit_counter <= 3'd7;
                            end else if (active_read) begin
                                state <= STATE_SHIFT_RX;
                                bit_counter <= 3'd7;
                            end else if (active_stop) begin
                                state <= STATE_STOP_0;
                            end else begin
                                busy  <= 1'b0;
                                state <= STATE_IDLE;
                            end
                        end else begin
                            substate <= substate + 1'b1;
                        end
                    end
                    
                    // --- WRITE BYTE ---
                    STATE_SHIFT_TX: begin
                        if (substate == 0) begin
                            scl_oe <= 1'b1; // SCL low
                            sda_oe <= ~tx_shift_reg[bit_counter]; // Set SDA out
                        end else if (substate == 1) begin
                            scl_oe <= 1'b0; // SCL high (float)
                        end
                        
                        if (substate == 3) begin
                            substate <= 0;
                            if (bit_counter == 0) begin
                                state <= STATE_ACK_TX;
                            end else begin
                                bit_counter <= bit_counter - 1'b1;
                            end
                        end else begin
                            substate <= substate + 1'b1;
                        end
                    end
                    
                    // --- GET ACK FROM SLAVE ---
                    STATE_ACK_TX: begin
                        if (substate == 0) begin
                            scl_oe <= 1'b1; // SCL low
                            sda_oe <= 1'b0; // Float SDA (receive mode)
                        end else if (substate == 1) begin
                            scl_oe <= 1'b0; // SCL high
                        end else if (substate == 2) begin
                            rx_ack_bit <= sda_in; // Sample ACK (0 = ACK, 1 = NACK)
                        end
                        
                        if (substate == 3) begin
                            scl_oe <= 1'b1; // Pull SCL low to complete the 9th clock cycle!
                            substate <= 0;
                            active_write <= 1'b0;
                            
                            if (active_stop) begin
                                state <= STATE_STOP_0;
                            end else begin
                                busy  <= 1'b0;
                                state <= STATE_IDLE;
                            end
                        end else begin
                            substate <= substate + 1'b1;
                        end
                    end
                    
                    // --- READ BYTE ---
                    STATE_SHIFT_RX: begin
                        if (substate == 0) begin
                            scl_oe <= 1'b1; // SCL low
                            sda_oe <= 1'b0; // Release SDA
                        end else if (substate == 1) begin
                            scl_oe <= 1'b0; // SCL high
                        end else if (substate == 2) begin
                            rx_shift_reg[bit_counter] <= sda_in; // Sample SDA
                        end
                        
                        if (substate == 3) begin
                            substate <= 0;
                            if (bit_counter == 0) begin
                                state <= STATE_ACK_RX;
                            end else begin
                                bit_counter <= bit_counter - 1'b1;
                            end
                        end else begin
                            substate <= substate + 1'b1;
                        end
                    end
                    
                    // --- SEND ACK TO SLAVE ---
                    STATE_ACK_RX: begin
                        if (substate == 0) begin
                            scl_oe <= 1'b1; // SCL low
                            sda_oe <= active_ack; // Send ACK/NACK (0 = ACK, 1 = NACK)
                        end else if (substate == 1) begin
                            scl_oe <= 1'b0; // SCL high
                        end
                        
                        if (substate == 3) begin
                            scl_oe <= 1'b1; // Pull SCL low to complete the 9th clock cycle!
                            substate <= 0;
                            active_read <= 1'b0;
                            data_out <= rx_shift_reg; // Save result register
                            
                            if (active_stop) begin
                                state <= STATE_STOP_0;
                            end else begin
                                busy  <= 1'b0;
                                state <= STATE_IDLE;
                            end
                        end else begin
                            substate <= substate + 1'b1;
                        end
                    end
                    
                    // --- STOP CONDITION ---
                    STATE_STOP_0: begin
                        // Phase 0: Pull SDA low while SCL is low
                        scl_oe <= 1'b1;
                        sda_oe <= 1'b1;
                        state  <= STATE_STOP_1;
                    end
                    STATE_STOP_1: begin
                        if (substate == 0) begin
                            scl_oe <= 1'b0; // Release SCL (goes high)
                        end else if (substate == 2) begin
                            sda_oe <= 1'b0; // Release SDA (goes high while SCL is high)
                        end
                        
                        if (substate == 3) begin
                            substate <= 0;
                            active_stop <= 1'b0;
                            busy  <= 1'b0;
                            state <= STATE_IDLE;
                        end else begin
                            substate <= substate + 1'b1;
                        end
                    end
                    
                    default: state <= STATE_IDLE;
                endcase
            end
        end
    end

endmodule

