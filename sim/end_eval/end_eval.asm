; End-evaluation program translated to the 8-register ISA.
; ISA differences: LDI replaces large ADDI immediates; ADD is naturally 8-bit
; modulo arithmetic; SHR is used for SRA because this test's shifted value is
; positive.  Values that would occupy R8-R15 are either reused or spilled.
;
; Register allocation: r0=0, r1=current value, r2=base, r3=R3, r4=5,
; r5=temporary/R5/R10/R12, r6=temporary/R6/R11/R13/R14, r7=R7/shift count.
; Proof locations: [base+8]=R9, [base+12]=saved R5, [base+16]=saved R7.

        LDI  r2, 0x64           ; base address 100
        LDI  r4, 5
        LDI  r6, 2
        LDI  r7, 10
        LDI  r1, 20             ; initialise MEM[base]
        STR  r1, [r2 + 0]
        LDI  r1, 50             ; initialise MEM[base+4]
        STR  r1, [r2 + 4]

        LDD  r1, [r2 + 0]       ; R1 = 20
        ADD  r3, r1, r4         ; R3 = 25
        SUB  r5, r3, r6         ; R5 = 23
        STR  r5, [r2 + 12]      ; preserve R5 before r5 is reused
        ADD  r7, r5, r7         ; R7 = 33 (ADDU equivalent)
        STR  r7, [r2 + 16]      ; preserve R7 before reuse as shift count
        SHL  r5, r7, r6         ; R9 = 33 << 2 = 132
        STR  r5, [r2 + 8]
        LDD  r5, [r2 + 4]       ; R10 = 50
        SUB  r6, r5, r1         ; R11 = 30
        ADD  r1, r1, r6         ; R1 = 50 (self-dependent)
        JZ   r1, SKIP
        LDD  r6, [r2 + 12]      ; recover original R5 = 23
        ADD  r5, r6, r3         ; R12 = 48
        SUB  r6, r5, r4         ; R13 = 43
        LDI  r7, 1
        SHR  r6, r6, r7         ; R14 = 21, equal to SRA for positive 43
        JMP  END
SKIP:   LDI  r7, 1
END:    HALT
