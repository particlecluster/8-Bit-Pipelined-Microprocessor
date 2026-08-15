; UART Transmit Test — sends "Hi!" over the UART TX line.
; r5 = base address of UART status register (0xFA, held in register because
;      LDD only has a 5-bit zero-extended offset, and 0xFA > 31).
; r2 = bit mask 0x02 (isolates the tx_ready bit from the status byte).
; r1 = byte to transmit.
; r3 = completion marker (0x42).
;
; Memory-mapped I/O addresses used:
;   0xFA = UART status  — status[1] = tx_ready, status[0] = rx_valid
;   0xFC = UART TX data — writing here sends one byte over the serial line
;   0xBE = result latch — written at program end to prove execution reached HALT
;
; Expected VCD evidence:
;   uart_tx toggles 3 times (start + 8 data + stop bits per byte)
;   memory[0xBE] = 0x42 at HALT
;   tx_ready deassertes then reasserts between each send

; ---- initialise ----
        LDI  r5, 0xFA           ; r5 = UART status address (needed as LDD base)
        LDI  r2, 0x02           ; r2 = tx_ready mask (bit 1 of status)
        LDI  r1, 0x48           ; r1 = 'H'  (0x48)

; ---- send 'H' ----
poll1:  LDD  r4, r5, 0          ; r4 = UART status  (addr = r5 + 0 = 0xFA)
        AND  r4, r4, r2         ; r4 = r4 & 0x02  (isolate tx_ready)
        JZ   r4, poll1          ; if tx_ready == 0, keep polling
        STD  r1, [0xFC]         ; transmit 'H'

; ---- send 'i' ----
        LDI  r1, 0x69           ; r1 = 'i'  (0x69)
poll2:  LDD  r4, r5, 0          ; read status
        AND  r4, r4, r2
        JZ   r4, poll2
        STD  r1, [0xFC]         ; transmit 'i'

; ---- send '!' ----
        LDI  r1, 0x21           ; r1 = '!'  (0x21)
poll3:  LDD  r4, r5, 0          ; read status
        AND  r4, r4, r2
        JZ   r4, poll3
        STD  r1, [0xFC]         ; transmit '!'

; ---- signal completion ----
        LDI  r3, 0x42           ; completion marker
        STD  r3, [0xBE]         ; memory[0xBE] = 0x42  (proves we reached end)
        HALT
