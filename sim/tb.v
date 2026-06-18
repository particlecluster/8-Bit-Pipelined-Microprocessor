`timescale 1ns/1ps

module cpu_tb;

    reg  clk, rst;
    wire motor_pwm_pin;

    CPU_Core dut (
        .clk          (clk),
        .rst          (rst),
        .motor_pwm_pin(motor_pwm_pin)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    `define REG(n) dut.u_RegFile.registers[n]
    `define MEM(a) dut.u_DMEM.memory[a]
    `define PWM    dut.u_DMEM.pwm_duty_cycle
    `define PC     dut.pc
    `define IMEM   dut.u_IMEM.memory

    task automatic check;
        input [255:0] label;
        input [7:0]   got;
        input [7:0]   expected;
        begin
            if (got === expected) begin
                $display("  [PASS] %0s | got=0x%02X", label, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0s | got=0x%02X  expected=0x%02X <<<", label, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // R-type: [15:11]=op [10:8]=rd [7:5]=rs1 [4:2]=rs2 [1:0]=00
    function automatic [15:0] enc_R;
        input [4:0] op; input [2:0] rd, rs1, rs2;
        enc_R = {op, rd, rs1, rs2, 2'b00};
    endfunction

    // I-type: [15:11]=op [10:8]=rd [7:0]=imm
    function automatic [15:0] enc_I;
        input [4:0] op; input [2:0] rd; input [7:0] imm;
        enc_I = {op, rd, imm};
    endfunction

    // Branch: [15:11]=op [10:8]=rs1 [7:0]=target
    function automatic [15:0] enc_B;
        input [4:0] op; input [2:0] rs1; input [7:0] target;
        enc_B = {op, rs1, target};
    endfunction

    localparam ADD   = 5'b0_0000,
               SUB   = 5'b0_0001,
               AND   = 5'b0_0010,
               ORR   = 5'b0_0011,
               XOR   = 5'b0_0100,
               SHL   = 5'b0_0101,
               SHR   = 5'b0_0110,
               LDI   = 5'b0_0111,
               LOAD  = 5'b0_1000,
               STORE = 5'b0_1001,
               JMP   = 5'b0_1010,
               BEQ   = 5'b0_1011,
               BNE   = 5'b0_1100,
               BGT   = 5'b0_1101,
               MUL   = 5'b1_0000,
               MAC   = 5'b1_0001,
               ROL   = 5'b1_0010,
               ROR   = 5'b1_0011;

    // Global scratch array — reused by every test
    reg [15:0] prog [0:63];
    integer i;

    task load_and_run;
        input integer len;
        input integer cycles;
        begin
            // Reset IMEM region used
            for (i = 0; i < 64; i = i + 1)
                `IMEM[i] = 16'h0000;
            // Load program words
            for (i = 0; i < len; i = i + 1)
                `IMEM[i] = prog[i];
            // Reset registers
            for (i = 0; i < 8; i = i + 1)
                dut.u_RegFile.registers[i] = 8'h00;
            // Reset data memory
            for (i = 0; i < 255; i = i + 1)
                dut.u_DMEM.memory[i] = 8'h00;
            dut.u_DMEM.pwm_duty_cycle = 8'h00;
            // Apply reset
            rst = 1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            rst = 0;
            // Run
            repeat(cycles) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        $dumpfile("cpu_tb.vcd");
        $dumpvars(0, cpu_tb);

        // Pre-zero everything
        for (i = 0; i < 256; i = i + 1) `IMEM[i] = 16'h0000;
        for (i = 0; i < 255; i = i + 1) dut.u_DMEM.memory[i] = 8'h00;
        for (i = 0; i < 8;   i = i + 1) dut.u_RegFile.registers[i] = 8'h00;

        $display("============================================================");
        $display("  CPU TESTBENCH START");
        $display("============================================================");

        // ------------------------------------------------------------
        // TEST 1 — RESET
        // ------------------------------------------------------------
        $display("\n[TEST 1] Reset — PC must be 0x00");
        rst = 1; repeat(4) @(posedge clk); #1;
        check("RESET_PC", `PC, 8'h00);
        rst = 0;

        // ------------------------------------------------------------
        // TEST 2 — LDI all 8 registers
        // ------------------------------------------------------------
        $display("\n[TEST 2] LDI — all 8 registers");
        prog[0] = enc_I(LDI, 3'd0, 8'hAA);
        prog[1] = enc_I(LDI, 3'd1, 8'h11);
        prog[2] = enc_I(LDI, 3'd2, 8'h22);
        prog[3] = enc_I(LDI, 3'd3, 8'h33);
        prog[4] = enc_I(LDI, 3'd4, 8'h44);
        prog[5] = enc_I(LDI, 3'd5, 8'h55);
        prog[6] = enc_I(LDI, 3'd6, 8'h66);
        prog[7] = enc_I(LDI, 3'd7, 8'h77);
        load_and_run(8, 12);
        check("LDI_R1", `REG(1), 8'h11);
        check("LDI_R2", `REG(2), 8'h22);
        check("LDI_R3", `REG(3), 8'h33);
        check("LDI_R4", `REG(4), 8'h44);
        check("LDI_R5", `REG(5), 8'h55);
        check("LDI_R6", `REG(6), 8'h66);
        check("LDI_R7", `REG(7), 8'h77);

        // ------------------------------------------------------------
        // TEST 3 — ADD / SUB
        // ------------------------------------------------------------
        $display("\n[TEST 3] ADD and SUB");
        prog[0] = enc_I(LDI, 3'd1, 8'h0F);
        prog[1] = enc_I(LDI, 3'd2, 8'h01);
        prog[2] = enc_R(ADD, 3'd3, 3'd1, 3'd2);
        prog[3] = enc_R(SUB, 3'd4, 3'd1, 3'd2);
        load_and_run(4, 8);
        check("ADD_0F+01", `REG(3), 8'h10);
        check("SUB_0F-01", `REG(4), 8'h0E);

        // ------------------------------------------------------------
        // TEST 4 — AND / ORR / XOR
        // ------------------------------------------------------------
        $display("\n[TEST 4] AND / ORR / XOR");
        prog[0] = enc_I(LDI, 3'd1, 8'hF0);
        prog[1] = enc_I(LDI, 3'd2, 8'h0F);
        prog[2] = enc_R(AND, 3'd3, 3'd1, 3'd2);
        prog[3] = enc_R(ORR, 3'd4, 3'd1, 3'd2);
        prog[4] = enc_R(XOR, 3'd5, 3'd1, 3'd2);
        prog[5] = enc_R(XOR, 3'd6, 3'd1, 3'd1);
        load_and_run(6, 10);
        check("AND_F0_0F",   `REG(3), 8'h00);
        check("ORR_F0_0F",   `REG(4), 8'hFF);
        check("XOR_F0_0F",   `REG(5), 8'hFF);
        check("XOR_SELF_0",  `REG(6), 8'h00);

        // ------------------------------------------------------------
        // TEST 5 — SHL / SHR
        // ------------------------------------------------------------
        $display("\n[TEST 5] SHL / SHR");
        prog[0] = enc_I(LDI, 3'd1, 8'h01);
        prog[1] = enc_I(LDI, 3'd2, 8'h04);
        prog[2] = enc_R(SHL, 3'd3, 3'd1, 3'd2);
        prog[3] = enc_R(SHR, 3'd4, 3'd3, 3'd2);
        prog[4] = enc_I(LDI, 3'd5, 8'hFF);
        prog[5] = enc_R(SHL, 3'd6, 3'd5, 3'd2);
        load_and_run(6, 10);
        check("SHL_01_by4", `REG(3), 8'h10);
        check("SHR_10_by4", `REG(4), 8'h01);
        check("SHL_FF_by4", `REG(6), 8'hF0);

        // ------------------------------------------------------------
        // TEST 6 — Overflow / Underflow
        // ------------------------------------------------------------
        $display("\n[TEST 6] Overflow / Underflow wrap");
        prog[0] = enc_I(LDI, 3'd1, 8'hFF);
        prog[1] = enc_I(LDI, 3'd2, 8'h01);
        prog[2] = enc_R(ADD, 3'd3, 3'd1, 3'd2);
        prog[3] = enc_I(LDI, 3'd4, 8'h00);
        prog[4] = enc_R(SUB, 3'd5, 3'd4, 3'd2);
        load_and_run(5, 9);
        check("ADD_OVERFLOW",  `REG(3), 8'h00);
        check("SUB_UNDERFLOW", `REG(5), 8'hFF);

        // ------------------------------------------------------------
        // TEST 7 — STORE / LOAD round-trip
        // ------------------------------------------------------------
        $display("\n[TEST 7] STORE then LOAD");
        prog[0] = enc_I(LDI,   3'd1, 8'hAB);
        prog[1] = enc_I(STORE, 3'd1, 8'h10);
        prog[2] = enc_I(LOAD,  3'd3, 8'h10);
        prog[3] = enc_I(LDI,   3'd2, 8'h00);
        prog[4] = enc_I(STORE, 3'd2, 8'h20);
        prog[5] = enc_I(LOAD,  3'd4, 8'h20);
        load_and_run(6, 10);
        check("STORE_MEM10",  `MEM(8'h10), 8'hAB);
        check("LOAD_R3",      `REG(3),     8'hAB);
        check("STORE_ZERO",   `MEM(8'h20), 8'h00);
        check("LOAD_ZERO_R4", `REG(4),     8'h00);

        // ------------------------------------------------------------
        // TEST 8 — MMIO PWM latch (0xFF)
        // ------------------------------------------------------------
        $display("\n[TEST 8] MMIO PWM latch");
        prog[0] = enc_I(LDI,   3'd1, 8'h80);
        prog[1] = enc_I(STORE, 3'd1, 8'hFF);
        prog[2] = enc_I(LDI,   3'd2, 8'hFF);
        prog[3] = enc_I(STORE, 3'd2, 8'hFF);
        prog[4] = enc_I(LOAD,  3'd3, 8'hFF);
        load_and_run(5, 9);
        check("PWM_LATCH_FF",   `PWM,    8'hFF);
        check("MMIO_READ_ZERO", `REG(3), 8'h00);

        // ------------------------------------------------------------
        // TEST 9 — BEQ taken (rs1 == 0)
        // ------------------------------------------------------------
        $display("\n[TEST 9] BEQ taken");
        prog[0] = enc_I(LDI, 3'd1, 8'h00);
        prog[1] = enc_B(BEQ, 3'd1, 8'h04);
        prog[2] = enc_I(LDI, 3'd5, 8'hDE);
        prog[3] = enc_I(LDI, 3'd5, 8'hAD);
        prog[4] = enc_I(LDI, 3'd6, 8'hBE);
        load_and_run(5, 8);
        check("BEQ_SKIP", `REG(5), 8'h00);
        check("BEQ_LAND", `REG(6), 8'hBE);

        // ------------------------------------------------------------
        // TEST 10 — BEQ not taken (rs1 != 0)
        // ------------------------------------------------------------
        $display("\n[TEST 10] BEQ not taken");
        prog[0] = enc_I(LDI, 3'd1, 8'h05);
        prog[1] = enc_B(BEQ, 3'd1, 8'h04);
        prog[2] = enc_I(LDI, 3'd5, 8'hCC);
        prog[3] = enc_I(LDI, 3'd6, 8'h00);
        load_and_run(4, 8);
        check("BEQ_NOT_TAKEN", `REG(5), 8'hCC);

        // ------------------------------------------------------------
        // TEST 11 — BNE taken (rs1 != 0)
        // ------------------------------------------------------------
        $display("\n[TEST 11] BNE taken");
        prog[0] = enc_I(LDI, 3'd1, 8'h07);
        prog[1] = enc_B(BNE, 3'd1, 8'h04);
        prog[2] = enc_I(LDI, 3'd5, 8'hDE);
        prog[3] = enc_I(LDI, 3'd5, 8'hAD);
        prog[4] = enc_I(LDI, 3'd6, 8'hBB);
        load_and_run(5, 8);
        check("BNE_SKIP", `REG(5), 8'h00);
        check("BNE_LAND", `REG(6), 8'hBB);

        // ------------------------------------------------------------
        // TEST 12 — BGT taken (positive signed)
        // ------------------------------------------------------------
        $display("\n[TEST 12] BGT taken (positive)");
        prog[0] = enc_I(LDI, 3'd1, 8'h7F);
        prog[1] = enc_B(BGT, 3'd1, 8'h04);
        prog[2] = enc_I(LDI, 3'd5, 8'hDE);
        prog[3] = enc_I(LDI, 3'd5, 8'hAD);
        prog[4] = enc_I(LDI, 3'd6, 8'hEE);
        load_and_run(5, 8);
        check("BGT_SKIP", `REG(5), 8'h00);
        check("BGT_LAND", `REG(6), 8'hEE);

        // ------------------------------------------------------------
        // TEST 13 — BGT not taken (negative signed)
        // ------------------------------------------------------------
        $display("\n[TEST 13] BGT not taken (negative)");
        prog[0] = enc_I(LDI, 3'd1, 8'h80);
        prog[1] = enc_B(BGT, 3'd1, 8'h04);
        prog[2] = enc_I(LDI, 3'd5, 8'hAA);
        prog[3] = enc_I(LDI, 3'd6, 8'h00);
        load_and_run(4, 8);
        check("BGT_NEG_NOT_TAKEN", `REG(5), 8'hAA);

        // ------------------------------------------------------------
        // TEST 14 — JMP unconditional
        // ------------------------------------------------------------
        $display("\n[TEST 14] JMP unconditional");
        prog[0] = enc_I(JMP, 3'd0, 8'h05);
        prog[1] = enc_I(LDI, 3'd1, 8'hDE);
        prog[2] = enc_I(LDI, 3'd1, 8'hAD);
        prog[3] = enc_I(LDI, 3'd1, 8'hBE);
        prog[4] = enc_I(LDI, 3'd1, 8'hEF);
        prog[5] = enc_I(LDI, 3'd2, 8'hCA);
        load_and_run(6, 6);
        check("JMP_SKIP", `REG(1), 8'h00);
        check("JMP_LAND", `REG(2), 8'hCA);

        // ------------------------------------------------------------
        // TEST 15 — MUL
        // ------------------------------------------------------------
        $display("\n[TEST 15] MUL (EXT)");
        prog[0] = enc_I(LDI, 3'd1, 8'h09);
        prog[1] = enc_I(LDI, 3'd2, 8'h07);
        prog[2] = enc_R(MUL, 3'd3, 3'd1, 3'd2);
        prog[3] = enc_I(LDI, 3'd4, 8'hFF);
        prog[4] = enc_I(LDI, 3'd5, 8'hFF);
        prog[5] = enc_R(MUL, 3'd6, 3'd4, 3'd5);
        load_and_run(6, 10);
        check("MUL_9x7",      `REG(3), 8'h3F);
        check("MUL_FFxFF_lo", `REG(6), 8'h01);

        // ------------------------------------------------------------
        // TEST 16 — MAC
        // ------------------------------------------------------------
        $display("\n[TEST 16] MAC (EXT)");
        prog[0] = enc_I(LDI, 3'd1, 8'h04);
        prog[1] = enc_I(LDI, 3'd2, 8'h03);
        prog[2] = enc_I(LDI, 3'd3, 8'h10);
        prog[3] = enc_R(MAC, 3'd3, 3'd1, 3'd2);
        load_and_run(4, 8);
        check("MAC_10+4x3", `REG(3), 8'h1C);

        // ------------------------------------------------------------
        // TEST 17 — ROL / ROR
        // ------------------------------------------------------------
        $display("\n[TEST 17] ROL / ROR (EXT)");
        prog[0] = enc_I(LDI, 3'd1, 8'hA1);
        prog[1] = enc_I(LDI, 3'd2, 8'h01);
        prog[2] = enc_R(ROL, 3'd3, 3'd1, 3'd2);
        prog[3] = enc_R(ROR, 3'd4, 3'd1, 3'd2);
        prog[4] = enc_I(LDI, 3'd5, 8'h00);
        prog[5] = enc_R(ROL, 3'd6, 3'd1, 3'd5);
        load_and_run(6, 10);
        check("ROL_A1_by1", `REG(3), 8'h43);
        check("ROR_A1_by1", `REG(4), 8'hD0);
        check("ROL_by0",    `REG(6), 8'hA1);

        // ------------------------------------------------------------
        // TEST 18 — Chained: (3+5)*2-4 = 12
        // ------------------------------------------------------------
        $display("\n[TEST 18] Chained ADD->MUL->SUB");
        prog[0] = enc_I(LDI, 3'd1, 8'h03);
        prog[1] = enc_I(LDI, 3'd2, 8'h05);
        prog[2] = enc_I(LDI, 3'd3, 8'h02);
        prog[3] = enc_I(LDI, 3'd4, 8'h04);
        prog[4] = enc_R(ADD, 3'd5, 3'd1, 3'd2);
        prog[5] = enc_R(MUL, 3'd6, 3'd5, 3'd3);
        prog[6] = enc_R(SUB, 3'd7, 3'd6, 3'd4);
        load_and_run(7, 12);
        check("CHAIN_ADD", `REG(5), 8'h08);
        check("CHAIN_MUL", `REG(6), 8'h10);
        check("CHAIN_SUB", `REG(7), 8'h0C);

        // ------------------------------------------------------------
        // TEST 19 — Multi-address STORE/LOAD independence
        // ------------------------------------------------------------
        $display("\n[TEST 19] Multi-address STORE/LOAD");
        prog[0] = enc_I(LDI,   3'd1, 8'hAA);
        prog[1] = enc_I(LDI,   3'd2, 8'hBB);
        prog[2] = enc_I(LDI,   3'd3, 8'hCC);
        prog[3] = enc_I(STORE, 3'd1, 8'h30);
        prog[4] = enc_I(STORE, 3'd2, 8'h31);
        prog[5] = enc_I(STORE, 3'd3, 8'h32);
        prog[6] = enc_I(LOAD,  3'd4, 8'h30);
        prog[7] = enc_I(LOAD,  3'd5, 8'h31);
        prog[8] = enc_I(LOAD,  3'd6, 8'h32);
        load_and_run(9, 14);
        check("ADDR_0x30", `REG(4), 8'hAA);
        check("ADDR_0x31", `REG(5), 8'hBB);
        check("ADDR_0x32", `REG(6), 8'hCC);

        // ------------------------------------------------------------
        // TEST 20 — XOR self-zero then BEQ
        // ------------------------------------------------------------
        $display("\n[TEST 20] XOR self-zero then BEQ");
        prog[0] = enc_I(LDI, 3'd1, 8'hFF);
        prog[1] = enc_R(XOR, 3'd1, 3'd1, 3'd1);
        prog[2] = enc_B(BEQ, 3'd1, 8'h04);
        prog[3] = enc_I(LDI, 3'd2, 8'hBA);
        prog[4] = enc_I(LDI, 3'd3, 8'hDA);
        load_and_run(5, 8);
        check("XOR_ZERO_SKIP", `REG(2), 8'h00);
        check("XOR_ZERO_LAND", `REG(3), 8'hDA);

        // ------------------------------------------------------------
        // TEST 21 — SUB self-zero then BEQ
        // ------------------------------------------------------------
        $display("\n[TEST 21] SUB self-zero then BEQ");
        prog[0] = enc_I(LDI, 3'd1, 8'h42);
        prog[1] = enc_R(SUB, 3'd2, 3'd1, 3'd1);
        prog[2] = enc_B(BEQ, 3'd2, 8'h04);
        prog[3] = enc_I(LDI, 3'd3, 8'hFE);
        prog[4] = enc_I(LDI, 3'd4, 8'h7A);
        load_and_run(5, 8);
        check("SUB_ZERO_SKIP", `REG(3), 8'h00);
        check("SUB_ZERO_LAND", `REG(4), 8'h7A);

        // ------------------------------------------------------------
        // TEST 22 — PWM sweep 0->7F->FF
        // ------------------------------------------------------------
        $display("\n[TEST 22] PWM duty sweep");
        prog[0] = enc_I(LDI,   3'd1, 8'h00);
        prog[1] = enc_I(STORE, 3'd1, 8'hFF);
        prog[2] = enc_I(LDI,   3'd1, 8'h7F);
        prog[3] = enc_I(STORE, 3'd1, 8'hFF);
        prog[4] = enc_I(LDI,   3'd1, 8'hFF);
        prog[5] = enc_I(STORE, 3'd1, 8'hFF);
        load_and_run(6, 10);
        check("PWM_100PCT", `PWM, 8'hFF);

        // ------------------------------------------------------------
        // TEST 23 — BNE not taken (rs1 == 0)
        // ------------------------------------------------------------
        $display("\n[TEST 23] BNE not taken (rs1==0)");
        prog[0] = enc_I(LDI, 3'd1, 8'h00);
        prog[1] = enc_B(BNE, 3'd1, 8'h04);
        prog[2] = enc_I(LDI, 3'd5, 8'h99);
        prog[3] = enc_I(LDI, 3'd6, 8'h00);
        load_and_run(4, 8);
        check("BNE_NOT_TAKEN", `REG(5), 8'h99);

        // ------------------------------------------------------------
        // SUMMARY
        // ------------------------------------------------------------
        $display("\n============================================================");
        $display("  RESULTS: %0d PASSED / %0d FAILED / %0d TOTAL",
                  pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d FAILED — CHECK ABOVE ***", fail_count);
        $display("============================================================\n");
        $finish;
    end

    initial begin
        #200000;
        $display("[WATCHDOG] Timeout.");
        $finish;
    end

endmodule
