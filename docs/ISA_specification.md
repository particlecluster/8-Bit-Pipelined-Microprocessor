### 1. Instruction Formats

Every instruction is 16 bits long, with the top 5 bits always defining the Opcode. The remaining 11 bits change depending on the instruction type:

* **R-Type (Register-to-Register):** `[15:11]` Opcode | `[10:8]` Rd | `[7:5]` Rs1 | `[4:2]` Rs2 | `[1:0]` 00
* **I-Type (Immediate/Math):** `[15:11]` Opcode | `[10:8]` Rd | `[7:0]` Imm8
* **M-Type (Memory/Addi):** `[15:11]` Opcode | `[10:8]` Rd/Rs | `[7:5]` Rs_Base | `[4:0]` Imm5
* **B-Type (Branching):** `[15:11]` Opcode | `[10:8]` Rs1 | `[7:0]` Imm8

---

### 2. The Complete ISA

#### Base Arithmetic & Logic (R-Type)

| Mnemonic | Args | Opcode (Bin) | Hex | Description |
| --- | --- | --- | --- | --- |
| **ADD** | `Rd, Rs1, Rs2` | `00000` | `0x00` | Addition: `Rd = Rs1 + Rs2` |
| **SUB** | `Rd, Rs1, Rs2` | `00001` | `0x01` | Subtraction: `Rd = Rs1 - Rs2` |
| **AND** | `Rd, Rs1, Rs2` | `00010` | `0x02` | Bitwise AND: `Rd = Rs1 & Rs2` |
| **ORR** | `Rd, Rs1, Rs2` | `00011` | `0x03` | Bitwise OR: `Rd = Rs1 |
| **XOR** | `Rd, Rs1, Rs2` | `00100` | `0x04` | Bitwise XOR: `Rd = Rs1 ^ Rs2` |
| **SHL** | `Rd, Rs1, Rs2` | `00101` | `0x05` | Shift Left: `Rd = Rs1 << Rs2[2:0]` |
| **SHR** | `Rd, Rs1, Rs2` | `00110` | `0x06` | Shift Right: `Rd = Rs1 >> Rs2[2:0]` |
| **SLT** | `Rd, Rs1, Rs2` | `01111` | `0x0F` | Set Less Than: `Rd = (Rs1 < Rs2) ? 1 : 0` |

#### Extended DSP Math (R-Type)

| Mnemonic | Args | Opcode (Bin) | Hex | Description |
| --- | --- | --- | --- | --- |
| **MUL** | `Rd, Rs1, Rs2` | `10000` | `0x10` | Multiply: `Rd = (Rs1 * Rs2)[7:0]` |
| **MAC** | `Rd, Rs1, Rs2` | `10001` | `0x11` | Multiply-Accumulate: `Rd = Rd + (Rs1 * Rs2)` |
| **ROL** | `Rd, Rs1, Rs2` | `10010` | `0x12` | Rotate Left by `Rs2[2:0]` |
| **ROR** | `Rd, Rs1, Rs2` | `10011` | `0x13` | Rotate Right by `Rs2[2:0]` |

#### Immediates & Memory (I-Type & M-Type)

| Mnemonic | Args | Opcode (Bin) | Hex | Description |
| --- | --- | --- | --- | --- |
| **LDI** | `Rd, Imm8` | `00111` | `0x07` | Load Immediate: `Rd = Imm8` |
| **ADDI** | `Rd, Rs1, Imm5` | `01110` | `0x0E` | Add Immediate: `Rd = Rs1 + Imm5` |
| **LOAD** | `Rd, Rb, Imm5` | `01000` | `0x08` | Load from Memory: `Rd = MEM[Rb + Imm5]` |
| **STORE** | `Rs, Rb, Imm5` | `01001` | `0x09` | Store to Memory: `MEM[Rb + Imm5] = Rs` |

#### Control Flow (B-Type & J-Type)

| Mnemonic | Args | Opcode (Bin) | Hex | Description |
| --- | --- | --- | --- | --- |
| **JMP** | `Imm8` | `01010` | `0x0A` | Unconditional Jump: `PC = Imm8` |
| **BEQ** | `Rs1, Imm8` | `01011` | `0x0B` | Branch if Equal to 0: `If (Rs1 == 0) PC = Imm8` |
| **BNE** | `Rs1, Imm8` | `01100` | `0x0C` | Branch if Not Equal to 0: `If (Rs1 != 0) PC = Imm8` |
| **BGT** | `Rs1, Imm8` | `01101` | `0x0D` | Branch if Greater than 0: `If (Rs1 > 0) PC = Imm8` |
| **HLT** | `None` | `11111` | `0x1F` | Halt: Freezes the Program Counter |

*(Note: Memory Address `0xFF` (255) is mapped to hardware PWM generator for motor control. Writing to it updates the duty cycle instead of storing it in standard RAM).*
