; Software TRAP exception test.
; Expected: EPC = 1, CAUSE = 3, memory[0xDD] = 1, memory[0xCC] = 0.

        LDD  r1, [r0 + 0x10]
        TRAP
        LDI  r2, 0x99
        STD  r2, [0xCC]

; Exception vector: 0x80
0x80:   MFC0 r4, CAUSE
        ADDI r4, r4, -1
        JZ   r4, overflow_handler
        MFC0 r4, CAUSE
        ADDI r4, r4, -2
        JZ   r4, illegal_handler
        JMP  trap_handler

overflow_handler:
        HALT

illegal_handler:
        HALT

trap_handler:
        MFC0 r5, EPC
        STD  r5, [0xDD]
        HALT
