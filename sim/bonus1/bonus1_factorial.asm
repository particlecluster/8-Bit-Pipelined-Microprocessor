; Bonus 1: recursive factorial using a software stack.
; r6 = stack pointer, r7 = link register, r1 = argument/result.
; Expected result: memory[0xA0] = fact(5) = 120.

        LDI  r6, 0x70
        LDI  r1, 5
        JAL  r7, fact
        STD  r1, [0xA0]
        HALT

fact:   JZ   r1, fact_base
        STR  r7, [r6 + 0]       ; push return address
        STR  r1, [r6 + 1]       ; push n
        ADDI r6, r6, -2
        ADDI r1, r1, -1
        JAL  r7, fact
        ADDI r6, r6, 2
        LDD  r2, [r6 + 1]       ; pop n
        MUL  r1, r2, r1
        LDD  r7, [r6 + 0]       ; pop return address
        JR   r7

fact_base:
        LDI  r1, 1
        JR   r7
