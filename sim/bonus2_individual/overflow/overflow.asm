; Arithmetic overflow exception test.
; Expected: EPC = 2, CAUSE = 1, memory[0xAA] = 0xFF, memory[0xAB] = 100.

        LDI  r1, 200
        LDI  r2, 100
        ADD  r3, r1, r2
        STD  r3, [0xAA]
        SUB  r4, r1, r2
        STD  r4, [0xAB]
        HALT

; Exception vector: 0x80
0x80:   MFC0 r4, CAUSE
        ADDI r4, r4, -1
        JZ   r4, overflow_handler
        HALT

overflow_handler:
        LDI  r3, 0xFF
        ERET
