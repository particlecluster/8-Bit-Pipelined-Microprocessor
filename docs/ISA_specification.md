### Instruction Format Reference

* **Instruction Length:** 16 bits
* **Opcode:** Bits `[15:11]` (5 bits)
* **Registers (`rd`, `rs1`, `rs2`):** 3 bits each (Registers `0-7`)
* **Padding:** Dashes (`-`) represent unused bits.

---

### 1. Base Arithmetic & Logic

| Instruction | Opcode `[15:11]` | Bit Layout | Operation |
| --- | --- | --- | --- |
| **ADD** | `00000` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = rs1 + rs2` |
| **SUB** | `00001` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = rs1 - rs2` |
| **AND** | `00010` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = rs1 & rs2` |
| **ORR** | `00011` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = rs1 | rs2` |
| **XOR** | `00100` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = rs1 ^ rs2` |
| **SHL** | `00101` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = rs1 << rs2[2:0]` |
| **SHR** | `00110` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = rs1 >> rs2[2:0]` |
| **SLT** | `01111` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = (rs1 < rs2) ? 1 : 0` (Signed) |
| **ADDI** | `01110` | `rd[10:8]` `rs1[7:5]` `imm[4:0]` | `rd = rs1 + imm` (Signed 5-bit) |

---

### 2. Extended DSP & Hardware Extensions

| Instruction | Opcode `[15:11]` | Bit Layout | Operation |
| --- | --- | --- | --- |
| **MUL** | `10000` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = (rs1 * rs2)[7:0]` |
| **MAC** | `10001` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = rd + (rs1 * rs2)[7:0]` |
| **ROL** | `10010` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = rs1` rotated left by `rs2[2:0]` |
| **ROR** | `10011` | `rd[10:8]` `rs1[7:5]` `rs2[4:2]` `--[1:0]` | `rd = rs1` rotated right by `rs2[2:0]` |

---

### 3. Memory & Data Movement

| Instruction | Opcode `[15:11]` | Bit Layout | Operation |
| --- | --- | --- | --- |
| **LDI** | `00111` | `rd[10:8]` `imm[7:0]` | `rd = imm` (8-bit immediate) |
| **LOAD** | `01000` | `rd[10:8]` `base[7:5]` `off[4:0]` | `rd = Mem[base + off]` |
| **STORE** | `01001` | `data[10:8]` `base[7:5]` `off[4:0]` | `Mem[base + off] = data` |

---

### 4. Control Flow (Branching & Jumps)

*Note: Branch instructions evaluate the register located in bits `[10:8]` against `0`.*

| Instruction | Opcode `[15:11]` | Bit Layout | Operation |
| --- | --- | --- | --- |
| **JMP** | `01010` | `---[10:8]` `imm[7:0]` | `PC = imm` |
| **BEQ** | `01011` | `rs1[10:8]` `imm[7:0]` | If `rs1 == 0`, `PC = imm` |
| **BNE** | `01100` | `rs1[10:8]` `imm[7:0]` | If `rs1 != 0`, `PC = imm` |
| **BGT** | `01101` | `rs1[10:8]` `imm[7:0]` | If `rs1 > 0`, `PC = imm` (Signed) |

---

### 5. System Controls

| Instruction | Opcode `[15:11]` | Bit Layout | Operation |
| --- | --- | --- | --- |
| **NOP** | `11110` | `-----------[10:0]` | No Operation (1-cycle delay) |
| **HLT** | `11111` | `-----------[10:0]` | Halts CPU Program Counter |
