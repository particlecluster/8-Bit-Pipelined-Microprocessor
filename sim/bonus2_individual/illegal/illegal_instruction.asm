; Illegal instruction exception test.
; Expected: EPC = 2, CAUSE = 2, memory[0xFF] = 0xEE, memory[0xBB] = 0.

        LDI  r1, 10
        LDI  r2, 20
        .word 0xD800
        ADD  r3, r1, r2
        STD  r3, [0xBB]

; Exception vector: 0x80
0x80:   MFC0 r4, CAUSE
        ADDI r4, r4, -2
        JZ   r4, illegal_handler
        HALT

illegal_handler:
        LDI  r5, 0xEE
        STD  r5, [0xFF]
        HALT
