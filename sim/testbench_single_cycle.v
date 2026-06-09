// ============================================================
//  tb_cpu_top.v  —  Comprehensive testbench for single-cycle CPU
//
//  ISA quick-reference (16-bit instruction word):
//    [15]    = 0 (unused)
//    [14:11] = opcode
//
//  R-type  (ADD/SUB/AND/OR/XOR/SHL/SHR/SAR/ADDS/SUBS):
//    [10:8] = rd   [7:5] = rs1   [4:2] = rs2   [1:0] = 00
//
//  I-type  (LDIMM):
//    [10:8] = rd   [7:0] = imm8
//
//  L-type  (LOAD):
//    [10:8] = rd   [7:5] = rs1   [4:0] = imm5
//
//  S-type  (STORE)  — fixed format:
//    [10:8] = rs2_data   [7:5] = rs1_base   [4:0] = imm5
//
//  B-type  (BEQ/BNE)  — encoding constraint:
//    [10:8] = ignored    [7:5] = rs1         [4:0] = imm5
//    rs2 for compare  = instr[4:2]  (overlaps imm5!)
//    Safe rule: only compare against r0; keep imm5[4:2]=000
//    i.e. offsets 1,2,3 are safe (5'b000_01, 5'b000_10, 5'b000_11)
//    branch_pc = pc_of_branch + sign_ext(imm5)
//
//  J-type  (JMP):
//    [7:5] = rs1   (jump_pc = regs[rs1], absolute)
//
//  NOT opcode: ALU supports it (alu_op=1010) but control_unit
//  has no case for it — documented as a known gap.
// ============================================================
`timescale 1ns/1ps

module tb_cpu_top;

    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------
    reg clk, rst;

    cpu_top DUT (
        .clk(clk),
        .rst(rst)
    );

    // --------------------------------------------------------
    // Clock — 10 ns period
    // --------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // --------------------------------------------------------
    // tick: advance N rising edges then settle 1 ns
    // --------------------------------------------------------
    task tick;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
            #1;
        end
    endtask

    // --------------------------------------------------------
    // do_reset: hold rst for 2 cycles then release
    // --------------------------------------------------------
    task do_reset;
        begin
            rst = 1;
            repeat(2) @(posedge clk);
            rst = 0;
            #1;
        end
    endtask

    // --------------------------------------------------------
    // Register / memory accessors
    // --------------------------------------------------------
    function [7:0] reg_rd;
        input [2:0] r;
        reg_rd = DUT.RF.regs[r];
    endfunction

    function [7:0] dmem_rd;
        input [7:0] addr;
        dmem_rd = DUT.DMEM.mem[addr];
    endfunction

    // --------------------------------------------------------
    // pass/fail counters
    // --------------------------------------------------------
    integer pass_count;
    integer fail_count;

    task check;
        input [31:0]  test_num;
        input [7:0]   got;
        input [7:0]   expected;
        input [239:0] label;
        begin
            if (got === expected) begin
                $display("PASS [%02d] %-30s  got=0x%02h", test_num, label, got);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [%02d] %-30s  got=0x%02h  expected=0x%02h",
                         test_num, label, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // --------------------------------------------------------
    // Instruction encoders
    // --------------------------------------------------------

    // R-type: ADD/SUB/AND/OR/XOR/SHL/SHR/SAR/ADDS/SUBS
    function [15:0] enc_r;
        input [3:0] op;
        input [2:0] rd, rs1, rs2;
        enc_r = {1'b0, op, rd, rs1, rs2, 2'b00};
    endfunction

    // LDIMM
    function [15:0] enc_ldimm;
        input [2:0] rd;
        input [7:0] imm8;
        enc_ldimm = {1'b0, 4'b0000, rd, imm8};
    endfunction

    // LOAD  rd, [rs1 + imm5]
    function [15:0] enc_load;
        input [2:0] rd, rs1;
        input [4:0] imm5;
        enc_load = {1'b0, 4'b1011, rd, rs1, imm5};
    endfunction

    // STORE  rs2_data, [rs1_base + imm5]
    function [15:0] enc_store;
        input [2:0] rs2_data, rs1_base;
        input [4:0] imm5;
        enc_store = {1'b0, 4'b1100, rs2_data, rs1_base, imm5};
    endfunction

    // BEQ  rs1, r0, imm5   (safe: compare against r0, offset 1-3)
    // branch_pc = pc_of_this_instr + sign_ext(imm5)
    function [15:0] enc_beq;
        input [2:0] rs1;
        input [4:0] imm5;   // imm5[4:2] must be 000 to keep rs2=r0
        enc_beq = {1'b0, 4'b1101, 3'b000, rs1, imm5};
    endfunction

    // BNE  rs1, r0, imm5
    function [15:0] enc_bne;
        input [2:0] rs1;
        input [4:0] imm5;
        enc_bne = {1'b0, 4'b1110, 3'b000, rs1, imm5};
    endfunction

    // JMP  rs1   (jump_pc = regs[rs1], absolute)
    function [15:0] enc_jmp;
        input [2:0] rs1;
        enc_jmp = {1'b0, 4'b1111, 3'b000, rs1, 5'b00000};
    endfunction

    // NOP — harmless LDIMM r0, 0x00
    function [15:0] nop;
        nop = {1'b0, 4'b0000, 3'b000, 8'h00};
    endfunction

    // --------------------------------------------------------
    // Helper: fill remainder of IMEM with NOPs from 'start'
    // --------------------------------------------------------
    integer fill_i;
    task fill_nop;
        input integer start;
        begin
            for (fill_i = start; fill_i < 256; fill_i = fill_i + 1)
                DUT.IMEM.mem[fill_i] = nop();
        end
    endtask

    // --------------------------------------------------------
    // MAIN TEST SEQUENCE
    // --------------------------------------------------------
    integer addr;

    initial begin
        pass_count = 0;
        fail_count = 0;

        // ====================================================
        // PROGRAM 1 — Basic arithmetic & logic
        //
        //  0  LDIMM r1, 0x0A          r1 = 10
        //  1  LDIMM r2, 0x03          r2 = 3
        //  2  ADD   r3, r1, r2        r3 = 13
        //  3  SUB   r4, r1, r2        r4 = 7
        //  4  AND   r5, r1, r2        r5 = 0x0A & 0x03 = 0x02
        //  5  OR    r6, r1, r2        r6 = 0x0A | 0x03 = 0x0B
        //  6  XOR   r7, r1, r2        r7 = 0x0A ^ 0x03 = 0x09
        //  7  SHL   r3, r1            r3 = 10 << 1 = 20
        //  8  SHR   r4, r1            r4 = 10 >> 1 = 5
        //  9  SAR   r5, r2            r5 = 3 >> 1 (arith) = 1
        //  10 ADDS  r6, r1, r2        r6 = 13
        //  11 SUBS  r7, r1, r2        r7 = 7
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0]  = enc_ldimm(3'd1, 8'h0A);
        DUT.IMEM.mem[1]  = enc_ldimm(3'd2, 8'h03);
        DUT.IMEM.mem[2]  = enc_r(4'b0001, 3'd3, 3'd1, 3'd2);  // ADD
        DUT.IMEM.mem[3]  = enc_r(4'b0011, 3'd4, 3'd1, 3'd2);  // SUB
        DUT.IMEM.mem[4]  = enc_r(4'b1000, 3'd5, 3'd1, 3'd2);  // AND
        DUT.IMEM.mem[5]  = enc_r(4'b1001, 3'd6, 3'd1, 3'd2);  // OR
        DUT.IMEM.mem[6]  = enc_r(4'b1010, 3'd7, 3'd1, 3'd2);  // XOR
        DUT.IMEM.mem[7]  = enc_r(4'b0101, 3'd3, 3'd1, 3'd0);  // SHL
        DUT.IMEM.mem[8]  = enc_r(4'b0110, 3'd4, 3'd1, 3'd0);  // SHR
        DUT.IMEM.mem[9]  = enc_r(4'b0111, 3'd5, 3'd2, 3'd0);  // SAR
        DUT.IMEM.mem[10] = enc_r(4'b0010, 3'd6, 3'd1, 3'd2);  // ADDS
        DUT.IMEM.mem[11] = enc_r(4'b0100, 3'd7, 3'd1, 3'd2);  // SUBS
        fill_nop(12);

        tick(12);

        $display("\n--- Program 1: Arithmetic & Logic ---");
        check(1,  reg_rd(3'd1), 8'd10,  "LDIMM r1=10");
        check(2,  reg_rd(3'd2), 8'd3,   "LDIMM r2=3");
        check(3,  reg_rd(3'd3), 8'd20,  "SHL r1<<1=20");   // r3 last written by SHL
        check(4,  reg_rd(3'd4), 8'd5,   "SHR r1>>1=5");    // r4 last written by SHR
        check(5,  reg_rd(3'd5), 8'd1,   "SAR r2>>1=1");    // r5 last written by SAR
        check(6,  reg_rd(3'd6), 8'd13,  "ADDS r1+r2=13");  // r6 last written by ADDS
        check(7,  reg_rd(3'd7), 8'd7,   "SUBS r1-r2=7");   // r7 last written by SUBS

        // ====================================================
        // PROGRAM 2 — STORE / LOAD basic
        //
        //  r1=0xAB, r2=5
        //  STORE r1 → mem[5+0]
        //  LOAD  r3 ← mem[5+0]
        //  r3 must equal 0xAB
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'hAB);
        DUT.IMEM.mem[1] = enc_ldimm(3'd2, 8'h05);
        DUT.IMEM.mem[2] = enc_store(3'd1, 3'd2, 5'd0);       // STORE r1, [r2+0]
        DUT.IMEM.mem[3] = enc_load (3'd3, 3'd2, 5'd0);       // LOAD  r3, [r2+0]
        fill_nop(4);

        tick(4);

        $display("\n--- Program 2: STORE / LOAD basic ---");
        check(8,  reg_rd(3'd3), 8'hAB, "LOAD back STORE");

        // ====================================================
        // PROGRAM 3 — STORE / LOAD with positive imm5 offset
        //
        //  base r1=0x10, store r2=0xCD at [base+3]=0x13
        //  then load into r3 from [base+3]
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h10);            // r1 = 0x10 (base)
        DUT.IMEM.mem[1] = enc_ldimm(3'd2, 8'hCD);            // r2 = 0xCD (data)
        DUT.IMEM.mem[2] = enc_store(3'd2, 3'd1, 5'd3);       // STORE r2, [r1+3] → mem[0x13]
        DUT.IMEM.mem[3] = enc_load (3'd3, 3'd1, 5'd3);       // LOAD  r3, [r1+3]
        fill_nop(4);

        tick(4);

        $display("\n--- Program 3: STORE/LOAD with imm5 offset ---");
        check(9,  dmem_rd(8'h13), 8'hCD, "mem[0x13]=0xCD");
        check(10, reg_rd(3'd3),   8'hCD, "LOAD[base+3]=0xCD");

        // ====================================================
        // PROGRAM 4 — Multiple STORE then LOAD all back
        //
        //  Write 0x11 → mem[1], 0x22 → mem[2], 0x33 → mem[3]
        //  then LOAD all three into r4, r5, r6
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0]  = enc_ldimm(3'd1, 8'h11);           // r1 = 0x11
        DUT.IMEM.mem[1]  = enc_ldimm(3'd2, 8'h22);           // r2 = 0x22
        DUT.IMEM.mem[2]  = enc_ldimm(3'd3, 8'h33);           // r3 = 0x33
        DUT.IMEM.mem[3]  = enc_ldimm(3'd7, 8'h01);           // r7 = 1 (base)
        DUT.IMEM.mem[4]  = enc_store(3'd1, 3'd7, 5'd0);      // mem[1] = r1
        DUT.IMEM.mem[5]  = enc_store(3'd2, 3'd7, 5'd1);      // mem[2] = r2
        DUT.IMEM.mem[6]  = enc_store(3'd3, 3'd7, 5'd2);      // mem[3] = r3
        DUT.IMEM.mem[7]  = enc_load (3'd4, 3'd7, 5'd0);      // r4 = mem[1]
        DUT.IMEM.mem[8]  = enc_load (3'd5, 3'd7, 5'd1);      // r5 = mem[2]
        DUT.IMEM.mem[9]  = enc_load (3'd6, 3'd7, 5'd2);      // r6 = mem[3]
        fill_nop(10);

        tick(10);

        $display("\n--- Program 4: Multiple STORE + LOAD ---");
        check(11, reg_rd(3'd4), 8'h11, "LOAD mem[1]=0x11");
        check(12, reg_rd(3'd5), 8'h22, "LOAD mem[2]=0x22");
        check(13, reg_rd(3'd6), 8'h33, "LOAD mem[3]=0x33");

        // ====================================================
        // PROGRAM 5 — r0 hardwired zero
        //
        //  LDIMM r0, 0xFF — must be silently ignored
        //  ADD   r1, r0, r0 → r1 = 0
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd0, 8'hFF);            // write r0 — ignored
        DUT.IMEM.mem[1] = enc_r(4'b0001, 3'd1, 3'd0, 3'd0);  // r1 = r0+r0 = 0
        fill_nop(2);

        tick(2);

        $display("\n--- Program 5: r0 hardwired zero ---");
        check(14, reg_rd(3'd0), 8'd0, "r0 stays 0 after LDIMM");
        check(15, reg_rd(3'd1), 8'd0, "r0+r0=0");

        // ====================================================
        // PROGRAM 6 — Overflow / carry flags (ADDS)
        //
        //  127 + 1 = 128 (0x80), signed overflow
        //  255 + 127 = 126 + carry out
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h7F);
        DUT.IMEM.mem[1] = enc_ldimm(3'd2, 8'h01);
        DUT.IMEM.mem[2] = enc_r(4'b0010, 3'd3, 3'd1, 3'd2);  // ADDS r3,r1,r2
        DUT.IMEM.mem[3] = enc_ldimm(3'd4, 8'hFF);
        DUT.IMEM.mem[4] = enc_r(4'b0010, 3'd5, 3'd4, 3'd1);  // ADDS r5,r4,r1
        fill_nop(5);

        tick(5);

        $display("\n--- Program 6: Overflow / carry (ADDS) ---");
        check(16, reg_rd(3'd3), 8'h80, "127+1=128 (overflow)");
        check(17, reg_rd(3'd5), 8'h7E, "255+127=126 (carry)");

        // ====================================================
        // PROGRAM 7 — SAR sign extension on negative number
        //
        //  r1 = 0x80 (-128 signed)
        //  SAR r2, r1 → 0xC0 (-64), MSB replicated
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h80);
        DUT.IMEM.mem[1] = enc_r(4'b0111, 3'd2, 3'd1, 3'd0);  // SAR r2, r1
        fill_nop(2);

        tick(2);

        $display("\n--- Program 7: SAR sign extension ---");
        check(18, reg_rd(3'd2), 8'hC0, "SAR(0x80)=0xC0");

        // ====================================================
        // PROGRAM 8 — LDIMM full 8-bit range
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'hDE);
        DUT.IMEM.mem[1] = enc_ldimm(3'd2, 8'hAD);
        DUT.IMEM.mem[2] = enc_ldimm(3'd3, 8'hBE);
        DUT.IMEM.mem[3] = enc_ldimm(3'd4, 8'hEF);
        fill_nop(4);

        tick(4);

        $display("\n--- Program 8: LDIMM full byte ---");
        check(19, reg_rd(3'd1), 8'hDE, "LDIMM 0xDE");
        check(20, reg_rd(3'd2), 8'hAD, "LDIMM 0xAD");
        check(21, reg_rd(3'd3), 8'hBE, "LDIMM 0xBE");
        check(22, reg_rd(3'd4), 8'hEF, "LDIMM 0xEF");

        // ====================================================
        // PROGRAM 9 — BEQ taken
        //
        //  r1 = 0  (zero)
        //  BEQ r1, r0, +2   → rs1=r1, rs2(implicit)=r0, offset=2
        //    ALU: rd1 - rd2 = r1 - r0 = 0 - 0 = 0 → zero=1 → branch taken
        //    branch_pc = pc(=1) + 2 = 3  → skip addr 2, land at addr 3
        //  addr 2: LDIMM r2, 0xFF  ← POISON (must NOT execute)
        //  addr 3: LDIMM r3, 0xBB  ← must execute
        //
        //  Expected: r2=0x00 (poison skipped), r3=0xBB
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h00);            // r1 = 0
        DUT.IMEM.mem[1] = enc_beq(3'd1, 5'b00010);           // BEQ r1,r0,+2
        DUT.IMEM.mem[2] = enc_ldimm(3'd2, 8'hFF);            // POISON
        DUT.IMEM.mem[3] = enc_ldimm(3'd3, 8'hBB);            // landing pad
        fill_nop(4);

        tick(4);

        $display("\n--- Program 9: BEQ taken ---");
        check(23, reg_rd(3'd2), 8'h00, "BEQ taken: poison skipped");
        check(24, reg_rd(3'd3), 8'hBB, "BEQ taken: landing pad executed");

        // ====================================================
        // PROGRAM 10 — BEQ not taken
        //
        //  r1 = 0x05  (non-zero)
        //  BEQ r1, r0, +2  → r1-r0 = 5 ≠ 0 → zero=0 → fall through
        //  addr 2: LDIMM r2, 0xCC  ← must execute (not skipped)
        //  addr 3: LDIMM r3, 0x00  ← also executes
        //
        //  Expected: r2=0xCC
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h05);
        DUT.IMEM.mem[1] = enc_beq(3'd1, 5'b00010);           // BEQ r1,r0,+2
        DUT.IMEM.mem[2] = enc_ldimm(3'd2, 8'hCC);            // must execute
        DUT.IMEM.mem[3] = enc_ldimm(3'd3, 8'h00);
        fill_nop(4);

        tick(4);

        $display("\n--- Program 10: BEQ not taken ---");
        check(25, reg_rd(3'd2), 8'hCC, "BEQ not taken: fallthrough executed");

        // ====================================================
        // PROGRAM 11 — BNE taken
        //
        //  r1 = 0x07  (non-zero)
        //  BNE r1, r0, +2  → r1-r0 = 7 ≠ 0 → zero=0 → branch taken
        //  addr 2: LDIMM r2, 0xFF  ← POISON
        //  addr 3: LDIMM r3, 0xDD  ← landing pad
        //
        //  Expected: r2=0x00 (skipped), r3=0xDD
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h07);
        DUT.IMEM.mem[1] = enc_bne(3'd1, 5'b00010);           // BNE r1,r0,+2
        DUT.IMEM.mem[2] = enc_ldimm(3'd2, 8'hFF);            // POISON
        DUT.IMEM.mem[3] = enc_ldimm(3'd3, 8'hDD);            // landing pad
        fill_nop(4);

        tick(4);

        $display("\n--- Program 11: BNE taken ---");
        check(26, reg_rd(3'd2), 8'h00, "BNE taken: poison skipped");
        check(27, reg_rd(3'd3), 8'hDD, "BNE taken: landing pad executed");

        // ====================================================
        // PROGRAM 12 — BNE not taken
        //
        //  r1 = 0x00  (zero)
        //  BNE r1, r0, +2  → r1-r0=0 → zero=1 → fall through
        //  addr 2: LDIMM r2, 0xEE  ← must execute
        //
        //  Expected: r2=0xEE
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h00);
        DUT.IMEM.mem[1] = enc_bne(3'd1, 5'b00010);           // BNE r1,r0,+2
        DUT.IMEM.mem[2] = enc_ldimm(3'd2, 8'hEE);            // must execute
        DUT.IMEM.mem[3] = enc_ldimm(3'd3, 8'h00);
        fill_nop(4);

        tick(4);

        $display("\n--- Program 12: BNE not taken ---");
        check(28, reg_rd(3'd2), 8'hEE, "BNE not taken: fallthrough executed");

        // ====================================================
        // PROGRAM 13 — JMP absolute via register
        //
        //  r1 = 5  (jump target address)
        //  JMP r1          → pc = regs[r1] = 5
        //  addr 2: LDIMM r2, 0xFF  ← POISON (skipped)
        //  addr 3: LDIMM r2, 0xFF  ← POISON (skipped)
        //  addr 4: LDIMM r2, 0xFF  ← POISON (skipped)
        //  addr 5: LDIMM r3, 0xA5  ← landing pad
        //
        //  Expected: r2=0x00 (all poisons skipped), r3=0xA5
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h05);            // r1 = 5 (target)
        DUT.IMEM.mem[1] = enc_jmp(3'd1);                     // JMP r1
        DUT.IMEM.mem[2] = enc_ldimm(3'd2, 8'hFF);            // POISON
        DUT.IMEM.mem[3] = enc_ldimm(3'd2, 8'hFF);            // POISON
        DUT.IMEM.mem[4] = enc_ldimm(3'd2, 8'hFF);            // POISON
        DUT.IMEM.mem[5] = enc_ldimm(3'd3, 8'hA5);            // landing pad
        fill_nop(6);

        tick(6);

        $display("\n--- Program 13: JMP absolute ---");
        check(29, reg_rd(3'd2), 8'h00, "JMP: all poisons skipped (r2=0)");
        check(30, reg_rd(3'd3), 8'hA5, "JMP: landing pad executed");

        // ====================================================
        // PROGRAM 14 — BEQ backward branch (loop once)
        //
        //  The loop runs exactly TWICE then exits via BNE fallthrough.
        //  Uses a counter in r3.
        //
        //  addr 0: LDIMM r1, 0x02   r1 = 2 (loop count)
        //  addr 1: LDIMM r3, 0x00   r3 = 0 (accumulator)
        //  --- loop top (addr 2) ---
        //  addr 2: ADD   r3, r3, r1 r3 += r1
        //  addr 3: SUB   r1, r1, r2 r1 -= 1  (r2=r0=0... need r2=1)
        //
        //  Simpler loop using BNE backward:
        //  addr 0: LDIMM r1, 0x03   r1 = 3
        //  addr 1: LDIMM r2, 0x01   r2 = 1
        //  --- loop top (addr 2) ---
        //  addr 2: ADD   r3, r3, r2 r3 += 1
        //  addr 3: SUB   r1, r1, r2 r1 -= 1
        //  addr 4: BNE   r1, r0, -2 if r1 != 0, jump back to addr 2
        //    offset = 2 - 4 = -2 → signed = 5'b11110
        //    BUT: instr[4:2] = 111 → rs2 = r7!
        //    That would compare r1 against r7 not r0.
        //    r7=0 after reset so it still works, but fragile.
        //
        //    Alternative: use offset -3 → 5'b11101 → instr[4:2]=111 same problem
        //    Negative offsets always have top bits set so rs2 != r0.
        //
        //  SOLUTION: use a forward structure with JMP for loop-back.
        //  addr 0: LDIMM r1, 0x03      r1 = 3
        //  addr 1: LDIMM r2, 0x01      r2 = 1
        //  addr 2: LDIMM r5, 0x02      r5 = 2 (loop top address)
        //  --- loop top (addr 2 is the jump target, start at addr 3) ---
        //  addr 3: ADD   r3, r3, r2    r3 += 1
        //  addr 4: SUB   r1, r1, r2    r1 -= 1
        //  addr 5: BEQ   r1, r0, +2   if r1==0, skip JMP, go to addr 7 (done)
        //    offset=2 → imm5=00010 → rs2=instr[4:2]=000=r0 ✓
        //  addr 6: JMP   r5           jump back to addr 2... wait r5=2 not 3
        //
        //  Let r5 hold addr 3:
        //  addr 0: LDIMM r1, 0x03
        //  addr 1: LDIMM r2, 0x01
        //  addr 2: LDIMM r5, 0x03      r5 = 3 (loop top address)
        //  addr 3: ADD   r3, r3, r2    r3 += 1   [loop top]
        //  addr 4: SUB   r1, r1, r2    r1 -= 1
        //  addr 5: BEQ   r1, r0, +2   if r1==0 jump to addr 7 (exit)
        //  addr 6: JMP   r5            jump back to addr 3
        //  addr 7: NOP                 [exit — r3 should be 3]
        //
        //  Expected: r3 = 3  (loop ran 3 times)
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h03);            // r1 = 3 (counter)
        DUT.IMEM.mem[1] = enc_ldimm(3'd2, 8'h01);            // r2 = 1
        DUT.IMEM.mem[2] = enc_ldimm(3'd5, 8'h03);            // r5 = 3 (loop top addr)
        DUT.IMEM.mem[3] = enc_r(4'b0001, 3'd3, 3'd3, 3'd2);  // ADD r3, r3, r2
        DUT.IMEM.mem[4] = enc_r(4'b0011, 3'd1, 3'd1, 3'd2);  // SUB r1, r1, r2
        DUT.IMEM.mem[5] = enc_beq(3'd1, 5'b00010);           // BEQ r1,r0,+2 → addr 7
        DUT.IMEM.mem[6] = enc_jmp(3'd5);                     // JMP r5 → addr 3
        DUT.IMEM.mem[7] = nop();                              // exit
        fill_nop(8);

        // 3 iterations: each iteration = 4 instructions (addr 3-6)
        // setup = 3 instr (addr 0-2), exit = 1 nop
        // total = 3 + (3*4) - 1 + 1 extra = ~15 cycles; give 20 to be safe
        tick(20);

        $display("\n--- Program 14: Loop (BEQ exit + JMP back) ---");
        check(31, reg_rd(3'd3), 8'h03, "Loop 3x: r3=3");
        check(32, reg_rd(3'd1), 8'h00, "Loop counter exhausted: r1=0");

        // ====================================================
        // PROGRAM 15 — Integration: compute → store → load →
        //              branch on result
        //
        //  Compute 0x12 + 0x34 = 0x46
        //  Store result at mem[0x20]
        //  Load it back into r4
        //  BNE r4, r0, +2 (result != 0 → skip poison, land at 0xAA)
        //  LDIMM r5, 0xAA
        //
        //  addr 0: LDIMM r1, 0x12
        //  addr 1: LDIMM r2, 0x34
        //  addr 2: ADD   r3, r1, r2    r3 = 0x46
        //  addr 3: LDIMM r6, 0x20     r6 = 0x20 (address)
        //  addr 4: STORE r3, [r6+0]   mem[0x20] = 0x46
        //  addr 5: LOAD  r4, [r6+0]   r4 = mem[0x20] = 0x46
        //  addr 6: BNE   r4, r0, +2   r4!=0 → skip addr 7, land at 8
        //  addr 7: LDIMM r5, 0xFF     POISON
        //  addr 8: LDIMM r5, 0xAA     landing pad
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h12);
        DUT.IMEM.mem[1] = enc_ldimm(3'd2, 8'h34);
        DUT.IMEM.mem[2] = enc_r(4'b0001, 3'd3, 3'd1, 3'd2);  // ADD
        DUT.IMEM.mem[3] = enc_ldimm(3'd6, 8'h20);
        DUT.IMEM.mem[4] = enc_store(3'd3, 3'd6, 5'd0);       // STORE r3,[r6+0]
        DUT.IMEM.mem[5] = enc_load (3'd4, 3'd6, 5'd0);       // LOAD  r4,[r6+0]
        DUT.IMEM.mem[6] = enc_bne(3'd4, 5'b00010);           // BNE r4,r0,+2
        DUT.IMEM.mem[7] = enc_ldimm(3'd5, 8'hFF);            // POISON
        DUT.IMEM.mem[8] = enc_ldimm(3'd5, 8'hAA);            // landing pad
        fill_nop(9);

        tick(9);

        $display("\n--- Program 15: Integration (compute/store/load/branch) ---");
        check(33, reg_rd(3'd3), 8'h46,       "ADD 0x12+0x34=0x46");
        check(34, dmem_rd(8'h20), 8'h46,     "STORE mem[0x20]=0x46");
        check(35, reg_rd(3'd4), 8'h46,       "LOAD r4=0x46");
        check(36, reg_rd(3'd5), 8'hAA,       "BNE taken: r5=0xAA");

        // ====================================================
        // PROGRAM 16 — SUB produces zero → BEQ taken
        //
        //  r1 = 0x0A, r2 = 0x0A
        //  SUB r3, r1, r2 → r3 = 0
        //  BEQ r3, r0, +2 → zero=1, branch taken, skip poison
        //  addr 3: LDIMM r4, 0xFF  POISON
        //  addr 4: LDIMM r4, 0x77  landing pad
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h0A);
        DUT.IMEM.mem[1] = enc_ldimm(3'd2, 8'h0A);
        DUT.IMEM.mem[2] = enc_r(4'b0011, 3'd3, 3'd1, 3'd2);  // SUB r3,r1,r2
        DUT.IMEM.mem[3] = enc_beq(3'd3, 5'b00010);           // BEQ r3,r0,+2
        DUT.IMEM.mem[4] = enc_ldimm(3'd4, 8'hFF);            // POISON
        DUT.IMEM.mem[5] = enc_ldimm(3'd4, 8'h77);            // landing pad
        fill_nop(6);

        tick(6);

        $display("\n--- Program 16: SUB zero → BEQ taken ---");
        check(37, reg_rd(3'd3), 8'h00, "SUB 10-10=0");
        check(38, reg_rd(3'd4), 8'h77, "BEQ(zero) taken: r4=0x77");

        // ====================================================
        // PROGRAM 17 — SUBS sets flags, result checked
        //
        //  0x10 - 0x20 = 0xF0 (underflow, borrow)
        //  0x05 - 0x05 = 0x00 (zero)
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h10);
        DUT.IMEM.mem[1] = enc_ldimm(3'd2, 8'h20);
        DUT.IMEM.mem[2] = enc_r(4'b0100, 3'd3, 3'd1, 3'd2);  // SUBS r3,r1,r2
        DUT.IMEM.mem[3] = enc_ldimm(3'd4, 8'h05);
        DUT.IMEM.mem[4] = enc_ldimm(3'd5, 8'h05);
        DUT.IMEM.mem[5] = enc_r(4'b0100, 3'd6, 3'd4, 3'd5);  // SUBS r6,r4,r5
        fill_nop(6);

        tick(6);

        $display("\n--- Program 17: SUBS result values ---");
        check(39, reg_rd(3'd3), 8'hF0, "SUBS 0x10-0x20=0xF0");
        check(40, reg_rd(3'd6), 8'h00, "SUBS 5-5=0");

        // ====================================================
        // PROGRAM 18 — Shift edge cases
        //
        //  SHL 0x80 → 0x00  (MSB shifted out, result zero)
        //  SHR 0x01 → 0x00  (LSB shifted out, result zero)
        //  SAR 0xFF → 0xFF  (-1 >> 1 = -1, MSB replicates)
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'h80);
        DUT.IMEM.mem[1] = enc_r(4'b0101, 3'd2, 3'd1, 3'd0);  // SHL r2,r1
        DUT.IMEM.mem[2] = enc_ldimm(3'd3, 8'h01);
        DUT.IMEM.mem[3] = enc_r(4'b0110, 3'd4, 3'd3, 3'd0);  // SHR r4,r3
        DUT.IMEM.mem[4] = enc_ldimm(3'd5, 8'hFF);
        DUT.IMEM.mem[5] = enc_r(4'b0111, 3'd6, 3'd5, 3'd0);  // SAR r6,r5
        fill_nop(6);

        tick(6);

        $display("\n--- Program 18: Shift edge cases ---");
        check(41, reg_rd(3'd2), 8'h00, "SHL 0x80=0x00");
        check(42, reg_rd(3'd4), 8'h00, "SHR 0x01=0x00");
        check(43, reg_rd(3'd6), 8'hFF, "SAR 0xFF=0xFF");

        // ====================================================
        // PROGRAM 19 — XOR self-clear
        //
        //  r1 XOR r1 = 0 (classic register clear idiom)
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'hA5);
        DUT.IMEM.mem[1] = enc_r(4'b1010, 3'd2, 3'd1, 3'd1);  // XOR r2,r1,r1
        fill_nop(2);

        tick(2);

        $display("\n--- Program 19: XOR self-clear ---");
        check(44, reg_rd(3'd2), 8'h00, "r1 XOR r1 = 0");

        // ====================================================
        // PROGRAM 20 — AND / OR boundary values
        //
        //  0xFF AND 0xAA = 0xAA
        //  0x00 OR  0x55 = 0x55
        //  0xFF AND 0x00 = 0x00
        //  0xFF OR  0x00 = 0xFF
        // ====================================================
        do_reset;

        DUT.IMEM.mem[0] = enc_ldimm(3'd1, 8'hFF);
        DUT.IMEM.mem[1] = enc_ldimm(3'd2, 8'hAA);
        DUT.IMEM.mem[2] = enc_ldimm(3'd3, 8'h00);
        DUT.IMEM.mem[3] = enc_ldimm(3'd4, 8'h55);
        DUT.IMEM.mem[4] = enc_r(4'b1000, 3'd5, 3'd1, 3'd2);  // AND r5,r1,r2
        DUT.IMEM.mem[5] = enc_r(4'b1001, 3'd6, 3'd3, 3'd4);  // OR  r6,r3,r4
        DUT.IMEM.mem[6] = enc_r(4'b1000, 3'd7, 3'd1, 3'd3);  // AND r7,r1,r3
        fill_nop(7);

        tick(7);

        $display("\n--- Program 20: AND/OR boundary values ---");
        check(45, reg_rd(3'd5), 8'hAA, "0xFF AND 0xAA=0xAA");
        check(46, reg_rd(3'd6), 8'h55, "0x00 OR 0x55=0x55");
        check(47, reg_rd(3'd7), 8'h00, "0xFF AND 0x00=0x00");

        // ====================================================
        // DOCUMENTED GAP: NOT instruction
        //
        //  The ALU correctly computes ~a when alu_op=1010.
        //  However, control_unit has NO case for a NOT opcode —
        //  no instruction in the ISA dispatches alu_op=1010.
        //  (XOR opcode 1010 maps to alu_op=1001, not 1010.)
        //  Fix: add a NOT opcode (e.g. 4'b1011 is currently LOAD
        //  so pick a new opcode, or repurpose an unused slot,
        //  then add a case in control_unit: reg_write=1, alu_op=4'b1010)
        // ====================================================
        $display("\n--- Documented gap: NOT ---");
        $display("NOTE  ALU has NOT (alu_op=1010) but no ISA opcode maps to it.");
        $display("NOTE  To add NOT: assign a free opcode, add a control_unit case");
        $display("NOTE  with reg_write=1, alu_op=4'b1010.");

        // ====================================================
        // DOCUMENTED DESIGN NOTE: BEQ/BNE encoding constraint
        //
        //  rs2 = instr[4:2] overlaps imm5 = instr[4:0].
        //  Safe only when comparing against r0 with offsets 1-3
        //  (imm5[4:2]=000 keeps rs2=r0).
        //  Negative offsets (looping back) set imm5[4]=1 so
        //  instr[4:2] = 1XX → rs2 = r4/r5/r6/r7, not r0.
        //  Recommendation: give BEQ/BNE their own format like STORE
        //  (separate compare-reg and offset fields).
        // ====================================================
        $display("\n--- Documented design note: BEQ/BNE encoding ---");
        $display("NOTE  BEQ/BNE: rs2=instr[4:2] overlaps imm5=instr[4:0].");
        $display("NOTE  Backward branches corrupt rs2 field.");
        $display("NOTE  Recommend: separate branch format, like S-type STORE fix.");

        // ====================================================
        // Summary
        // ====================================================
        $display("\n==========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("==========================================\n");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED — check output above");

        $finish;
    end

    // --------------------------------------------------------
    // Watchdog
    // --------------------------------------------------------
    initial begin
        #200000;
        $display("TIMEOUT — simulation exceeded 200 us");
        $finish;
    end

    // --------------------------------------------------------
    // Waveform
    // --------------------------------------------------------
    initial begin
        $dumpfile("cpu_tb.vcd");
        $dumpvars(0, tb_cpu_top);
    end

endmodule
