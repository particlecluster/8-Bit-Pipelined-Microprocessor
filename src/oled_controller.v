`timescale 1ns / 1ps
`default_nettype none

module OLED_Controller #(
    parameter integer SYS_CLK_FREQ = 25_000_000,
    parameter integer I2C_CLK_FREQ = 400_000
) (
    input  wire       clk,
    input  wire       rst,
    
    // Accel inputs from CPU
    input  wire [7:0] accel_x,
    input  wire [7:0] accel_y,
    
    // I2C physical lines (to be connected to tristates at top level)
    input  wire       scl_in,
    output reg        scl_oe,
    input  wire       sda_in,
    output reg        sda_oe
);

    // Timing parameters: Tick runs at 4x the SCL frequency
    localparam integer TICK_DIVIDER = SYS_CLK_FREQ / (I2C_CLK_FREQ * 4);
    
    reg [$clog2(TICK_DIVIDER)-1:0] clk_divider;
    reg i2c_tick;
    
    always @(posedge clk) begin
        if (rst) begin
            clk_divider <= 0;
            i2c_tick <= 1'b0;
        end else begin
            i2c_tick <= 1'b0;
            if (clk_divider == TICK_DIVIDER - 1) begin
                clk_divider <= 0;
                i2c_tick <= 1'b1;
            end else begin
                clk_divider <= clk_divider + 1'b1;
            end
        end
    end

    // ROM containing SSD1306 Initialization commands (25 bytes)
    wire [7:0] init_rom [0:24];
    assign init_rom[0]  = 8'hAE; // Display OFF
    assign init_rom[1]  = 8'hD5; // Set Display Clock Divide Ratio
    assign init_rom[2]  = 8'h80;
    assign init_rom[3]  = 8'hA8; // Set Multiplex Ratio (64)
    assign init_rom[4]  = 8'h3F;
    assign init_rom[5]  = 8'hD3; // Set Display Offset (0)
    assign init_rom[6]  = 8'h00;
    assign init_rom[7]  = 8'h40; // Set Start Line (0)
    assign init_rom[8]  = 8'h8D; // Charge Pump Enable
    assign init_rom[9]  = 8'h14;
    assign init_rom[10] = 8'h20; // Memory Addressing Mode (Page)
    assign init_rom[11] = 8'h02;
    assign init_rom[12] = 8'hA1; // Segment Re-map (0xA1 = column 127 is SEG0)
    assign init_rom[13] = 8'hC8; // COM Output Scan Direction (remapped)
    assign init_rom[14] = 8'hDA; // Set COM Pins Hardware Configuration
    assign init_rom[15] = 8'h12;
    assign init_rom[16] = 8'h81; // Contrast
    assign init_rom[17] = 8'hCF;
    assign init_rom[18] = 8'hD9; // Pre-charge Period
    assign init_rom[19] = 8'hF1;
    assign init_rom[20] = 8'hDB; // VCOMH Deselect Level
    assign init_rom[21] = 8'h40;
    assign init_rom[22] = 8'hA4; // Entire Display ON Resume
    assign init_rom[23] = 8'hA6; // Normal Display Mode
    assign init_rom[24] = 8'hAF; // Display ON

    // SSD1306 State Machine States
    localparam STATE_POWERON    = 4'd0;
    localparam STATE_PREPARE    = 4'd1;
    localparam STATE_TX_START   = 4'd2;
    localparam STATE_TX_BYTE    = 4'd3;
    localparam STATE_TX_ACK     = 4'd4;
    localparam STATE_TX_STOP    = 4'd5;
    localparam STATE_NEXT_BYTE  = 4'd6;
    localparam STATE_NEXT_PHASE = 4'd7;

    reg [3:0]  state;
    reg [1:0]  substate; // Quarter-cycles of a bit (0 to 3)
    reg [2:0]  bit_counter;
    
    // Main variables
    reg [23:0] poweron_timer; // ~50ms power-on delay
    reg [7:0]  tx_buffer [0:130];
    reg [7:0]  tx_count;
    reg [7:0]  byte_ptr;
    reg [7:0]  current_byte;
    
    // Drawing states
    reg        initialized;
    reg [2:0]  current_page;
    reg [3:0]  phase; // 0: Send Init, 1: Send Cursor, 2: Send Data
    
    // On-the-fly math variables
    integer    col_idx;
    reg signed [15:0] temp_mult;
    reg signed [7:0]  H_line;
    reg        [7:0]  data_byte;
    integer    bit_idx;
    reg signed [7:0]  y_row;
    
    always @(posedge clk) begin
        if (rst) begin
            state           <= STATE_POWERON;
            substate        <= 0;
            bit_counter     <= 0;
            scl_oe          <= 1'b0;
            sda_oe          <= 1'b0;
            poweron_timer   <= 0;
            initialized     <= 1'b0;
            current_page    <= 0;
            phase           <= 0;
            byte_ptr        <= 0;
            tx_count        <= 0;
            current_byte    <= 0;
        end else begin
            case (state)
                // Wait 50ms for SSD1306 power stability
                STATE_POWERON: begin
                    if (poweron_timer == 24'd1_250_000) begin // 1.25M cycles @ 25MHz = 50ms
                        state <= STATE_PREPARE;
                        phase <= 0;
                    end else begin
                        poweron_timer <= poweron_timer + 1'b1;
                    end
                end
                
                // Prepare the packet buffer to transmit
                STATE_PREPARE: begin
                    byte_ptr <= 0;
                    if (phase == 0) begin
                        // Load Initialization sequence
                        tx_buffer[0] <= 8'h78; // I2C Address (0x3C << 1)
                        tx_buffer[1] <= 8'h00; // Control Byte (Co = 0, D/C# = 0)
                        tx_buffer[2]  <= init_rom[0];  tx_buffer[3]  <= init_rom[1];  tx_buffer[4]  <= init_rom[2];
                        tx_buffer[5]  <= init_rom[3];  tx_buffer[6]  <= init_rom[4];  tx_buffer[7]  <= init_rom[5];
                        tx_buffer[8]  <= init_rom[6];  tx_buffer[9]  <= init_rom[7];  tx_buffer[10] <= init_rom[8];
                        tx_buffer[11] <= init_rom[9];  tx_buffer[12] <= init_rom[10]; tx_buffer[13] <= init_rom[11];
                        tx_buffer[14] <= init_rom[12]; tx_buffer[15] <= init_rom[13]; tx_buffer[16] <= init_rom[14];
                        tx_buffer[17] <= init_rom[15]; tx_buffer[18] <= init_rom[16]; tx_buffer[19] <= init_rom[17];
                        tx_buffer[20] <= init_rom[18]; tx_buffer[21] <= init_rom[19]; tx_buffer[22] <= init_rom[20];
                        tx_buffer[23] <= init_rom[21]; tx_buffer[24] <= init_rom[22]; tx_buffer[25] <= init_rom[23];
                        tx_buffer[26] <= init_rom[24];
                        tx_count     <= 27;
                        state        <= STATE_TX_START;
                    end else if (phase == 1) begin
                        // Set column and page address cursor
                        tx_buffer[0] <= 8'h78;
                        tx_buffer[1] <= 8'h00;
                        tx_buffer[2] <= 8'hB0 | current_page; // Page select
                        tx_buffer[3] <= 8'h00; // Column lower address (0)
                        tx_buffer[4] <= 8'h10; // Column upper address (0)
                        tx_count     <= 5;
                        state        <= STATE_TX_START;
                    end else if (phase == 2) begin
                        // Generate and load data frame for current page
                        tx_buffer[0] <= 8'h78;
                        tx_buffer[1] <= 8'h40; // Control Byte (Co = 0, D/C# = 1 -> data stream)
                        
                        // Generate 128 column bytes on the fly based on accelerometer X/Y tilt
                        for (col_idx = 0; col_idx < 128; col_idx = col_idx + 1) begin
                            // H(x) = 32 + (accel_x * (col_idx - 64) / 128)
                            // We use $signed for correct tilt direction
                            temp_mult = $signed(accel_x) * $signed(col_idx - 128'd64);
                            H_line = 8'd32 + temp_mult[13:7];
                            
                            // Generate byte representing 8 vertical pixels of current page
                            data_byte = 8'h00;
                            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                                y_row = (current_page * 8) + bit_idx;
                                if (y_row >= H_line) begin
                                    data_byte[bit_idx] = 1'b1; // Liquid
                                end else begin
                                    data_byte[bit_idx] = 1'b0; // Air
                                end
                            end
                            tx_buffer[col_idx + 2] <= data_byte;
                        end
                        tx_count <= 130;
                        state    <= STATE_TX_START;
                    end
                end
                
                // I2C Transmission: START
                STATE_TX_START: begin
                    if (i2c_tick) begin
                        if (substate == 0) begin
                            sda_oe <= 1'b1; // Pull SDA low
                            scl_oe <= 1'b0;
                        end else if (substate == 2) begin
                            scl_oe <= 1'b1; // Pull SCL low
                        end
                        
                        if (substate == 3) begin
                            substate <= 0;
                            state    <= STATE_TX_BYTE;
                            current_byte <= tx_buffer[byte_ptr];
                            bit_counter  <= 3'd7;
                        end else begin
                            substate <= substate + 1'b1;
                        end
                    end
                end
                
                // I2C Transmission: Write 8 bits
                STATE_TX_BYTE: begin
                    if (i2c_tick) begin
                        if (substate == 0) begin
                            scl_oe <= 1'b1;
                            sda_oe <= ~current_byte[bit_counter]; // Set SDA out
                        end else if (substate == 1) begin
                            scl_oe <= 1'b0; // SCL high
                        end
                        
                        if (substate == 3) begin
                            substate <= 0;
                            if (bit_counter == 0) begin
                                state <= STATE_TX_ACK;
                            end else begin
                                bit_counter <= bit_counter - 1'b1;
                            end
                        end else begin
                            substate <= substate + 1'b1;
                        end
                    end
                end
                
                // I2C Transmission: Wait for Slave ACK
                STATE_TX_ACK: begin
                    if (i2c_tick) begin
                        if (substate == 0) begin
                            scl_oe <= 1'b1;
                            sda_oe <= 1'b0; // Release SDA
                        end else if (substate == 1) begin
                            scl_oe <= 1'b0; // SCL high
                        end
                        
                        if (substate == 3) begin
                            scl_oe <= 1'b1; // Pull SCL low to complete the 9th bit clock
                            substate <= 0;
                            state  <= STATE_NEXT_BYTE;
                        end else begin
                            substate <= substate + 1'b1;
                        end
                    end
                end
                
                // Move to next byte or finish transaction
                STATE_NEXT_BYTE: begin
                    if (byte_ptr == tx_count - 1) begin
                        state <= STATE_TX_STOP;
                    end else begin
                        byte_ptr <= byte_ptr + 1'b1;
                        current_byte <= tx_buffer[byte_ptr + 1'b1];
                        bit_counter  <= 3'd7;
                        state        <= STATE_TX_BYTE;
                    end
                end
                
                // I2C Transmission: STOP
                STATE_TX_STOP: begin
                    if (i2c_tick) begin
                        if (substate == 0) begin
                            scl_oe <= 1'b1;
                            sda_oe <= 1'b1; // Pull SDA low
                        end else if (substate == 1) begin
                            scl_oe <= 1'b0; // Release SCL high
                        end else if (substate == 2) begin
                            sda_oe <= 1'b0; // Release SDA high (while SCL is high)
                        end
                        
                        if (substate == 3) begin
                            substate <= 0;
                            state    <= STATE_NEXT_PHASE;
                        end else begin
                            substate <= substate + 1'b1;
                        end
                    end
                end
                
                // Determine next drawing phase
                STATE_NEXT_PHASE: begin
                    if (phase == 0) begin
                        // Done initializing! Move to frame loop
                        initialized <= 1'b1;
                        phase        <= 1;
                        current_page <= 0;
                        state        <= STATE_PREPARE;
                    end else if (phase == 1) begin
                        // Done sending cursor! Now send the data bytes for this page
                        phase <= 2;
                        state <= STATE_PREPARE;
                    end else if (phase == 2) begin
                        // Done sending page data! Move to next page
                        if (current_page == 7) begin
                            current_page <= 0;
                        end else begin
                            current_page <= current_page + 1'b1;
                        end
                        phase <= 1; // Go back to setting cursor for new page
                        state <= STATE_PREPARE;
                    end
                end
                
                default: state <= STATE_POWERON;
            endcase
        end
    end

endmodule
