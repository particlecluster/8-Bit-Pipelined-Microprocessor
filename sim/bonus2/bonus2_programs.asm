; Bonus-task programs for the 8-bit CPU.
; Instruction format used here: rd = bits [10:8], rs1 = [7:5], rs2 = [4:2].
; JAL/JR use r7 as the link register.  Branch and JAL offsets are relative to
; the current instruction PC.  Exception vector = 0x80.

; ============================================================================
; bonus_factorial.hex -- recursive fact(5), expected result: memory[0xA0] = 120
; r6 is a descending stack pointer.  Each recursive frame saves n and r7.
; ============================================================================
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

; ============================================================================
; Exception images share this handler at 0x80.  It conditionally dispatches
; based on CAUSE: 1=overflow, 2=illegal instruction, 3=TRAP.
; ============================================================================
exception_handler:
0x80:   MFC0 r4, CAUSE
        ADDI r4, r4, -1
        JZ   r4, overflow_handler
        MFC0 r4, CAUSE
        ADDI r4, r4, -2
        JZ   r4, illegal_handler
        JMP  trap_handler
overflow_handler:
        LDI  r3, 0xFF             ; clamp overflowing result
        ERET
illegal_handler:
        LDI  r5, 0xEE
        STD  r5, [0xFF]           ; error marker, then safely stop
        HALT
trap_handler:
        MFC0 r5, EPC
        STD  r5, [0xDD]
        HALT

; bonus_overflow.hex
        LDI  r1, 200
        LDI  r2, 100
        ADD  r3, r1, r2            ; overflow at PC 2
        STD  r3, [0xAA]            ; receives handler's 0xFF
        SUB  r4, r1, r2
        STD  r4, [0xAB]            ; must remain 100
        HALT

; bonus_illegal.hex
        LDI  r1, 10
        LDI  r2, 20
        .word 0xD800               ; unsupported opcode 11011, fault at PC 2
        ADD  r3, r1, r2            ; must never execute
        STD  r3, [0xBB]            ; must remain 0

; bonus_trap.hex
        LDD  r1, [r0 + 0x10]       ; RAM is initialized to 0
        TRAP                        ; deliberate software exception at PC 1
        LDI  r2, 0x99
        STD  r2, [0xCC]            ; must remain 0
