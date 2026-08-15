        LDI  R6, 0x70
        LDI  R1, 5
        JAL  R7, fact
        STD  R1, 0xA0
        HALT

fact:  
        JZ   R1, fact_base
        STR  R7, R6, 0
        STR  R1, R6, 1
        ADDI R6, R6, -2
        ADDI R1, R1, -1
        JAL  R7, fact
        ADDI R6, R6, 2
        LDD  R2, R6, 1
        MUL  R1, R2, R1
        LDD  R7, R6, 0
        JR   R7

fact_base:
        LDI  R1, 1
        JR   R7