**Changes applied:**

1. **New Instructions:** Added `JAL` and `JR` to reflect your newly implemented subroutine hardware.
2. **Memory Update:** Updated `LDD` from an `I-Type` (absolute addressing) to an `M-Type` (base + displacement) to match the pointer logic we fixed for the call stack.
3. **Register Slots:** For `JR`, `JZ`, `JNZ`, `JGT`, and `STD`, the source register (`Rs1`) is explicitly mapped to the `ddd` (bits [10:8]) slot, matching your `rs1_src = 1` decoding trick.

**Legend:** `d` = Rd (Destination), `1` = Rs1 (Source 1), `2` = Rs2 (Source 2 / Base), `i` = Immediate bit, `x` = Unused/Ignored.

| Mnemonic | Encoding (16-bit) | Type | Operation |
| --- | --- | --- | --- |
| **ADD** | `00000 ddd 111 222 xx` | R-Type | `Rd = Rs1 + Rs2` |
| **SUB** | `00001 ddd 111 222 xx` | R-Type | `Rd = Rs1 - Rs2` |
| **AND** | `00010 ddd 111 222 xx` | R-Type | `Rd = Rs1 & Rs2` |
| **OR** | `00011 ddd 111 222 xx` | R-Type | `Rd = Rs1 |
| **XOR** | `00100 ddd 111 222 xx` | R-Type | `Rd = Rs1 ^ Rs2` |
| **SHL** | `00101 ddd 111 222 xx` | R-Type | `Rd = Rs1 << Rs2[2:0]` |
| **SHR** | `00110 ddd 111 222 xx` | R-Type | `Rd = Rs1 >> Rs2[2:0]` |
| **LDI** | `00111 ddd iiiiiiii` | I-Type | `Rd = Imm8` |
| **LDD** | `01000 ddd 111 iiiii` | M-Type | `Rd = MEM[Rs1 + zext(Imm5)]` |
| **STR** | `01001 111 222 iiiii` | M-Type | `MEM[Rs2 + zext(Imm5)] = Rs1` |
| **JMP** | `01010 xxx iiiiiiii` | I-Type | `PC = PC + sext(Imm8)` |
| **JZ** | `01011 111 iiiiiiii` | I-Type | `If (Rs1 == 0) PC = PC + sext(Imm8)` |
| **JNZ** | `01100 111 iiiiiiii` | I-Type | `If (Rs1 != 0) PC = PC + sext(Imm8)` |
| **JGT** | `01101 111 iiiiiiii` | I-Type | `If (Rs1 > 0) PC = PC + sext(Imm8)` |
| **ADDI** | `01110 ddd 111 iiiii` | M-Type | `Rd = Rs1 + sext(Imm5)` |
| **SLT** | `01111 ddd 111 222 xx` | R-Type | `Rd = (Rs1 < Rs2) ? 1 : 0` (Signed) |
| **MUL** | `10000 ddd 111 222 xx` | R-Type | `Rd = (Rs1 * Rs2)[7:0]` |
| **MAC** | `10001 ddd 111 222 xx` | R-Type | `Rd = Rd + (Rs1 * Rs2)[7:0]` |
| **ROL** | `10010 ddd 111 222 xx` | R-Type | Rotate Left `Rs1` by `Rs2[2:0]` |
| **ROR** | `10011 ddd 111 222 xx` | R-Type | Rotate Right `Rs1` by `Rs2[2:0]` |
| **RETI** | `10100 xxxxxxxxxxx` | S-Type | Return from Interrupt (`PC = EPC`) |
| **STD** | `10101 111 iiiiiiii` | I-Type | `MEM[Imm8] = Rs1` |
| **JAL** | `10110 ddd iiiiiiii` | I-Type | `Rd = PC + 1`, `PC = PC + sext(Imm8)` |
| **JR** | `10111 111 xxxxxxxx` | I-Type | `PC = Rs1` |
| **HALT** | `11111 xxxxxxxxxxx` | S-Type | Freeze Program Counter |
