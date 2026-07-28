Here is the updated table.

**Changes applied:**

1. **Branches:** Updated `JMP`, `JZ`, `JNZ`, and `JGT` to reflect your new PC-relative offset logic (`PC = PC + sext(Imm8)`).
2. **Missing Instruction:** Added `STD` (Store Direct) which was missing from your list but present in your Verilog datapath.
3. **Mnemonics:** Renamed `LSL` → `SHL`, `LSR` → `SHR`, and `CMP_LT` → `SLT` to exactly match your Verilog decoding aliases.

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
| **LDD** | `01000 ddd iiiiiiii` | I-Type | `Rd = MEM[Imm8]` |
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
| **HALT** | `11111 xxxxxxxxxxx` | S-Type | Freeze Program Counter |
