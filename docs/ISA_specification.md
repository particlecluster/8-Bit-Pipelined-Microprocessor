# Instruction Set Architecture (ISA) Specification

## 1. Overview

This custom architecture is an 8-bit Data, 16-bit Instruction single-cycle processor designed for embedded control applications (including hardware-accelerated DSP tasks and MMIO motor PWM control).

* **Word Size:** 8-bit data path
* **Instruction Size:** 16-bit fixed length
* **Address Space:** 8-bit program address (256 instructions maximum), 8-bit data address space (256 bytes SRAM + MMIO registers)
* **Register File:** 8 general-purpose 8-bit registers ($R_0$ to $R_7$) with 3 asynchronous read ports and 1 synchronous write port.

---

## 2. Instruction Formats

Instructions are exactly 16 bits wide and are classified into three types depending on field mappings:

### R-Type (Register-Register Operations)

Used for standard arithmetic, logic, and ISA-extended DSP execution.

```
 15          11 10      8 7        5 4        2 1      0
+--------------+---------+----------+----------+--------+
|    Opcode    |   rd    |   rs1    |   rs2    | Unused |
+--------------+---------+----------+----------+--------+

```

### I-Type / Memory / Branch (Immediate / Absolute Encoding)

Used for data movement (`LDI`, `LOAD`, `STORE`), absolute unconditional control flow (`JMP`), and relative zero-bound branches (`BEQ`, `BNE`, `BGT`).

```
 15          11 10      8 7                                 0
+--------------+---------+-----------------------------------+
|    Opcode    |   rd* |          8-bit Immediate          |
+--------------+---------+-----------------------------------+

```

**Note: For Branch/Store operations, the `rd` bitfield [10:8] serves as `rs1` (source evaluation register).*

---

## 3. Opcode Map & Execution Truth Table

The opcode space is defined by a 5-bit indicator (`Opcode[4:0]`), where `Opcode[4]` serves as the **ISA Extension Flag (EXT)**.

| Opcode (Binary) | Mnemonic | Type | Operands | Operation | Description |
| --- | --- | --- | --- | --- | --- |
| **`0_0000`** | ADD | R | `rd, rs1, rs2` | $R[rd] \leftarrow R[rs1] + R[rs2]$ | 8-bit Addition |
| **`0_0001`** | SUB | R | `rd, rs1, rs2` | $R[rd] \leftarrow R[rs1] - R[rs2]$ | 8-bit Subtraction |
| **`0_0010`** | AND | R | `rd, rs1, rs2` | $R[rd] \leftarrow R[rs1] \ \& \ R[rs2]$ | Bitwise AND |
| **`0_0011`** | ORR | R | `rd, rs1, rs2` | $R[rd] \leftarrow R[rs1] \ \| \ R[rs2$ | Bitwise OR |
| **`0_0100`** | XOR | R | `rd, rs1, rs2` | $R[rd] \leftarrow R[rs1] \ \oplus \ R[rs2]$ | Bitwise XOR |
| **`0_0101`** | SHL | R | `rd, rs1, rs2` | $R[rd] \leftarrow R[rs1] \ll R[rs2][2:0]$ | Logical Shift Left |
| **`0_0110`** | SHR | R | `rd, rs1, rs2` | $R[rd] \leftarrow R[rs1] \gg R[rs2][2:0]$ | Logical Shift Right |
| **`0_0111`** | LDI | I | `rd, imm` | $R[rd] \leftarrow \text{imm}$ | Load Immediate |
| **`0_1000`** | LOAD | I | `rd, imm` | $R[rd] \leftarrow \text{Mem}[\text{imm}]$ | Load Data from Memory |
| **`0_1001`** | STORE | I | `rs1, imm` | $\text{Mem}[\text{imm}] \leftarrow R[rs1]$ | Store Data to Memory |
| **`0_1010`** | JMP | I | `imm` | $\text{PC} \leftarrow \text{imm}$ | Unconditional Absolute Jump |
| **`0_1011`** | BEQ | I | `rs1, imm` | $\text{if } (R[rs1] == 0) \ \text{PC} \leftarrow \text{imm}$ | Branch if Equal to Zero |
| **`0_1100`** | BNE | I | `rs1, imm` | $\text{if } (R[rs1] \neq 0) \ \text{PC} \leftarrow \text{imm}$ | Branch if Not Equal to Zero |
| **`0_1101`** | BGT | I | `rs1, imm` | $\text{if } (\$signed(R[rs1]) > 0) \ \text{PC} \leftarrow \text{imm}$ | Branch if Greater than Zero |
| **`1_0000`** | MUL | R | `rd, rs1, rs2` | $R[rd] \leftarrow (R[rs1] \times R[rs2])[7:0]$ | Lower 8-bit Hardware Multiplication |
| **`1_0001`** | MAC | R | `rd, rs1, rs2` | $R[rd] \leftarrow R[rd] + (R[rs1] \times R[rs2])[7:0]$ | Multiply-Accumulate (Uses Port `rd3` Read) |
| **`1_0010`** | ROL | R | `rd, rs1, rs2` | $R[rd] \leftarrow (R[rs1] \text{ rotl } R[rs2][2:0])$ | Rotate Left |
| **`1_0011`** | ROR | R | `rd, rs1, rs2` | $R[rd] \leftarrow (R[rs1] \text{ rotr } R[rs2][2:0])$ | Rotate Right |

---

## 4. Architectural Control Signal Matrix

The internal Control Unit decodes execution paths using the following control rules:

| Opcode Family / Instruction | reg_we | mem_we | alu_b_src | res_src | pc_src | rs1_src | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Base / EXT R-Type** | 1 | 0 | 0 | `00` | 0 | 0 | ALU Result $\rightarrow$ Register file. `rs1` sourced from `[7:5]`. |
| **`LDI`** | 1 | 0 | X | `10` | 0 | 0 | Immediate $\rightarrow$ Register file. |
| **`LOAD`** | 1 | 0 | X | `01` | 0 | 0 | SRAM $\rightarrow$ Register file. |
| **`STORE`** | 0 | 1 | X | `XX` | 0 | 1 | Register value $\rightarrow$ SRAM. Source `rs1` fetched from `[10:8]`. |
| **`JMP`** | 0 | 0 | X | `XX` | 1 | 0 | Immediate $\rightarrow$ Program Counter. |
| **Conditional Branches** | 0 | 0 | 1 | `XX` | $\text{Flag}$ | 1 | Evaluates `rs1` out of `[10:8]` against Zero ($8'h00$). |

### Control Wire Definitions:

* **`reg_we`**: Register File Write Enable.
* **`mem_we`**: Data Memory Write Enable.
* **`alu_b_src`**: Selects input `b` of ALU ($0 = \text{Register File Port 2}, 1 = \text{Zero Byte Constant } 8'h00$).
* **`res_src[1:0]`**: Write-back multiplexer selector ($00 = \text{ALU Output}, 01 = \text{Data Memory Out}, 10 = \text{Immediate Value}$).
* **`pc_src`**: Determines instruction flow ($0 = \text{PC} + 1, 1 = \text{Immediate Jump Destination}$).
* **`rs1_src`**: Multiplexes `rs1` source tracking ($0 = \text{Bits [7:5]}, 1 = \text{Bits [10:8]}$).

---

## 5. Memory-Mapped I/O (MMIO) Hardware Latches

The system allocates the top address of the 8-bit memory configuration space to communicate directly with structural hardware functions outside the core CPU.

| Memory Address | Access Type | Function Name | Bit-Width | Linked Hardware Periphery |
| --- | --- | --- | --- | --- |
| **`0x00` - `0xFE**` | R/W | Internal SRAM | 8-bit | Standard volatile data retention (255 bytes). |
| **`0xFF`** | W Only | `pwm_duty_cycle` | 8-bit | Hardware-attached DC Motor Controller (e.g., DRV8833 driver pipeline). |
| **`0xFF`** | R Only | Fault / Null | 8-bit | Returns continuous low data value ($8'h00$). |

### PWM Latch Operation:

Writing an 8-bit integer value directly to address `0xFF` overrides normal memory storage and locks the value straight into the active **PWM_Generator Counter Comparator Register**.

* An entry of `8'h00` generates a static **0% low output pulse**.
* An entry of `8'hFF` yields a high continuous **100% duty cycle configuration**.
