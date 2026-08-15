`timescale 1ns / 1ps
`default_nettype none

// ===========================================================================
// 8x8 LED Matrix Controller (Ultra-Smooth 2x2 Dot Spirit Level)
// Features:
//   1. 2-Stage Cascaded Q8.8 Fixed-Point EMA Filter -> Silky analog motion
//   2. Amplitude Hysteresis (Schmitt Trigger) -> Zero boundary flickering
//   3. Temporal Debounce Filter (16 ms) -> Eliminates transient hand jitter
//   4. Optimized Sensitivity -> Reaches all 4 outer edges comfortably at ~20Â°â€“25Â°
//   5. Drive Polarity -> Column Anodes (Active HIGH), Row Cathodes (Active LOW)
// ===========================================================================
module LED_Matrix_Controller (
    input  wire       clk,          // 25 MHz system clock
    input  wire       rst,          // Synchronous active-high reset
    
    // Accelerometer values from CPU/I2C (signed 8-bit from MPU6050)
    input  wire [7:0] accel_x,
    input  wire [7:0] accel_y,
    
    // Physical matrix pins
    // matrix_rows: PMOD JC (Row 0 = Top, Row 7 = Bottom) -> Cathodes (Active LOW = 0)
    // matrix_cols: PMOD JD (Col 0 = Left, Col 7 = Right) -> Anodes (Active HIGH = 1)
    output reg  [7:0] matrix_rows,
    output reg  [7:0] matrix_cols
);

    // -----------------------------------------------------------------------
    // 1. Column Scanning Multiplexer: 1 kHz scan rate (125 Hz frame rate)
    // -----------------------------------------------------------------------
    localparam integer SCAN_TICKS = 25000; // 25,000 cycles @ 25 MHz = 1 ms/column
    
    reg [15:0] scan_counter;
    reg [2:0]  active_col;
    reg        tick_1ms;
    
    always @(posedge clk) begin
        if (rst) begin
            scan_counter <= 16'd0;
            active_col   <= 3'd0;
            tick_1ms     <= 1'b0;
        end else begin
            tick_1ms <= 1'b0;
            if (scan_counter >= SCAN_TICKS - 1) begin
                scan_counter <= 16'd0;
                active_col   <= active_col + 3'd1;
                tick_1ms     <= 1'b1;
            end else begin
                scan_counter <= scan_counter + 16'd1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // 2. Cascaded 2-Stage Q8.8 Fixed-Point EMA Low-Pass Filter
    // -----------------------------------------------------------------------
    // Stage 1 (128-sample EMA): Eliminates high-frequency noise & quantization steps
    // Stage 2 (32-sample EMA): Smooths velocity & provides 2nd-order response
    wire signed [15:0] x_in = { {8{accel_x[7]}}, accel_x, 8'd0 };
    wire signed [15:0] y_in = { {8{accel_y[7]}}, accel_y, 8'd0 };

    reg signed [15:0] stage1_x, stage1_y;
    reg signed [15:0] stage2_x, stage2_y;
    
    always @(posedge clk) begin
        if (rst) begin
            stage1_x <= 16'sd0;
            stage1_y <= 16'sd0;
            stage2_x <= 16'sd0;
            stage2_y <= 16'sd0;
        end else if (tick_1ms) begin
            // Stage 1: alpha = 1/128
            stage1_x <= stage1_x + ((x_in - stage1_x) >>> 7);
            stage1_y <= stage1_y + ((y_in - stage1_y) >>> 7);
            
            // Stage 2: alpha = 1/32
            stage2_x <= stage2_x + ((stage1_x - stage2_x) >>> 5);
            stage2_y <= stage2_y + ((stage1_y - stage2_y) >>> 5);
        end
    end

    // Extract ultra-smoothed 8-bit signed acceleration
    wire signed [7:0] ax = stage2_x[15:8];
    wire signed [7:0] ay = stage2_y[15:8];

    // -----------------------------------------------------------------------
    // 3. Amplitude Hysteresis (Schmitt Trigger Target State Machine)
    // -----------------------------------------------------------------------
    // Deadzone: [-7, +7] -> Completely locked at center when resting
    // Step 1: Threshold = Â±7 LSB (Release back to center = Â±4 LSB)
    // Step 2: Threshold = Â±13 LSB (Release = Â±10 LSB)
    // Step 3 (Edge): Threshold = Â±19 LSB (Release = Â±16 LSB) -> Reaches border rows/cols!
    // -----------------------------------------------------------------------
    reg [2:0] target_r0;
    reg [2:0] target_c0;

    // Row (X-axis: Forward / Backward)
    always @(posedge clk) begin
        if (rst) begin
            target_r0 <= 3'd3; // Center
        end else if (tick_1ms) begin
            case (target_r0)
                3'd3: begin // Center (Rows 3, 4)
                    if (ax < -8'sd7)       target_r0 <= 3'd2; // Forward tilt
                    else if (ax > 8'sd7)   target_r0 <= 3'd4; // Backward tilt
                end
                3'd2: begin // Forward Step 1 (Rows 2, 3)
                    if (ax < -8'sd13)      target_r0 <= 3'd1;
                    else if (ax > -8'sd4)  target_r0 <= 3'd3; // Return to center
                end
                3'd1: begin // Forward Step 2 (Rows 1, 2)
                    if (ax < -8'sd19)      target_r0 <= 3'd0; // Reaches TOP edge!
                    else if (ax > -8'sd10) target_r0 <= 3'd2;
                end
                3'd0: begin // TOP EDGE (Rows 0, 1)
                    if (ax > -8'sd16)      target_r0 <= 3'd1;
                end
                3'd4: begin // Backward Step 1 (Rows 4, 5)
                    if (ax > 8'sd13)       target_r0 <= 3'd5;
                    else if (ax < 8'sd4)   target_r0 <= 3'd3; // Return to center
                end
                3'd5: begin // Backward Step 2 (Rows 5, 6)
                    if (ax > 8'sd19)       target_r0 <= 3'd6; // Reaches BOTTOM edge!
                    else if (ax < 8'sd10)  target_r0 <= 3'd4;
                end
                3'd6: begin // BOTTOM EDGE (Rows 6, 7)
                    if (ax < 8'sd16)       target_r0 <= 3'd5;
                end
                default: target_r0 <= 3'd3;
            endcase
        end
    end

    // Column (Y-axis: Left / Right)
    always @(posedge clk) begin
        if (rst) begin
            target_c0 <= 3'd3; // Center
        end else if (tick_1ms) begin
            case (target_c0)
                3'd3: begin // Center (Cols 3, 4)
                    if (ay < -8'sd7)       target_c0 <= 3'd2; // Left tilt
                    else if (ay > 8'sd7)   target_c0 <= 3'd4; // Right tilt
                end
                3'd2: begin // Left Step 1 (Cols 2, 3)
                    if (ay < -8'sd13)      target_c0 <= 3'd1;
                    else if (ay > -8'sd4)  target_c0 <= 3'd3; // Return to center
                end
                3'd1: begin // Left Step 2 (Cols 1, 2)
                    if (ay < -8'sd19)      target_c0 <= 3'd0; // Reaches LEFT edge!
                    else if (ay > -8'sd10) target_c0 <= 3'd2;
                end
                3'd0: begin // LEFT EDGE (Cols 0, 1)
                    if (ay > -8'sd16)      target_c0 <= 3'd1;
                end
                3'd4: begin // Right Step 1 (Cols 4, 5)
                    if (ay > 8'sd13)       target_c0 <= 3'd5;
                    else if (ay < 8'sd4)   target_c0 <= 3'd3; // Return to center
                end
                3'd5: begin // Right Step 2 (Cols 5, 6)
                    if (ay > 8'sd19)       target_c0 <= 3'd6; // Reaches RIGHT edge!
                    else if (ay < 8'sd10)  target_c0 <= 3'd4;
                end
                3'd6: begin // RIGHT EDGE (Cols 6, 7)
                    if (ay < 8'sd16)       target_c0 <= 3'd5;
                end
                default: target_c0 <= 3'd3;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // 4. Temporal Debounce Filter (16 ms Stability Verification)
    // -----------------------------------------------------------------------
    // Position change must be stable for 16 consecutive ms (2 full matrix frames)
    // before updating the output display, completely filtering out hand tremor
    reg [2:0] r0, c0;
    reg [2:0] prev_target_r, prev_target_c;
    reg [4:0] stable_cnt_r, stable_cnt_c;

    always @(posedge clk) begin
        if (rst) begin
            r0            <= 3'd3;
            c0            <= 3'd3;
            prev_target_r <= 3'd3;
            prev_target_c <= 3'd3;
            stable_cnt_r  <= 5'd0;
            stable_cnt_c  <= 5'd0;
        end else if (tick_1ms) begin
            // Row temporal debounce (16 ms)
            if (target_r0 == r0) begin
                stable_cnt_r  <= 5'd0;
                prev_target_r <= target_r0;
            end else if (target_r0 == prev_target_r) begin
                if (stable_cnt_r >= 5'd15) begin
                    r0           <= target_r0;
                    stable_cnt_r <= 5'd0;
                end else begin
                    stable_cnt_r <= stable_cnt_r + 5'd1;
                end
            end else begin
                prev_target_r <= target_r0;
                stable_cnt_r  <= 5'd0;
            end

            // Column temporal debounce (16 ms)
            if (target_c0 == c0) begin
                stable_cnt_c  <= 5'd0;
                prev_target_c <= target_c0;
            end else if (target_c0 == prev_target_c) begin
                if (stable_cnt_c >= 5'd15) begin
                    c0           <= target_c0;
                    stable_cnt_c <= 5'd0;
                end else begin
                    stable_cnt_c <= stable_cnt_c + 5'd1;
                end
            end else begin
                prev_target_c <= target_c0;
                stable_cnt_c  <= 5'd0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // 5. Glitch-Free Registered Matrix Output Drive
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            matrix_cols <= 8'h00;
            matrix_rows <= 8'hFF;
        end else begin
            // Anodes (Columns): Active HIGH (only active column is 1, rest 0)
            matrix_cols <= 8'h00;
            matrix_cols[active_col] <= 1'b1;

            // Cathodes (Rows): Active LOW (selected rows 0, inactive rows 1)
            matrix_rows <= 8'hFF;
            if (active_col == c0 || active_col == (c0 + 3'd1)) begin
                matrix_rows[r0]        <= 1'b0;
                matrix_rows[r0 + 3'd1] <= 1'b0;
            end
        end
    end

endmodule

