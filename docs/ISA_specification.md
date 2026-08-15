# 16-bit Pipelined Microprocessor Instruction Set Architecture (ISA)

## Architecture Summary
- **Instruction Width:** 16 bits
- **Data Path Width:** 8 bits
- **Address Bus Width:** 8 bits (256-byte Memory Space)
- **General Purpose Registers:** 8 x 8-bit Registers (`R0` – `R7`)
  - `R0`: Hardwired to constant `0` (Writes ignored, reads always return `0`)
  - `R1` – `R5`: General Purpose Registers
  - `R6`: Stack Pointer / Scratch Register
  - `R7`: Link Register (Return address for `JAL` instructions)
- **Special Registers (CP0 Coprocessor 0):**
  - `exception_epc`: Exception Program Counter
  - `exception_cause`: Exception Cause Register (`1` = Overflow, `2` = Illegal Instruction, `3` = Software Trap)
  - `epc`: Interrupt Return Address Register

---

## Instruction Formats

Instructions are 16 bits wide with a 5-bit opcode field (`inst[15:11]`).

### 1. Register Format (R-Type)
Used for 3-register arithmetic, logic, shift, rotate, comparison, and MAC operations.
```text
 15        11 10      8 7        5 4        2 1  0
+------------+---------+----------+----------+----+
|   Opcode   |   Rd    |   Rs1    |   Rs2    | -- |
+------------+---------+----------+----------+----+
```

### 2. Immediate Format (I-Type)
Used for loading 8-bit immediates directly into registers or CP0 register reads.
```text
 15        11 10      8 7                         0
+------------+---------+---------------------------+
|   Opcode   |   Rd    |      8-bit Immediate      |
+------------+---------+---------------------------+
```

### 3. ADDI / Offset Memory Format (ADDI-Type)
Used for register-immediate addition and base-displacement memory loads (`LDD`).
```text
 15        11 10      8 7        5 4              0
+------------+---------+----------+---------------+
|   Opcode   |   Rd    |   Rs1    | 5-bit Imm     |
+------------+---------+----------+---------------+
```

### 4. Branch / Store Direct Format (Branch-Type)
Used for branches, relative jumps, subroutine calls (`JAL`), and direct memory stores (`STD`).
```text
 15        11 10      8 7                         0
+------------+---------+---------------------------+
|   Opcode   |   Rs1   |    8-bit Imm / Target     |
+------------+---------+---------------------------+
```

### 5. Jump Register / System Format (Sys-Type)
Used for indirect jumps (`JR`) and system control instructions.
```text
 15        11 10      8 7                         0
+------------+---------+---------------------------+
|   Opcode   |   Rs1   |       Unused (0x00)       |
+------------+---------+---------------------------+
```

---

## Master Instruction Table

| Opcode (Bin) | Opcode (Hex) | Mnemonic | Format | Assembly Syntax | Operation / Description |
| :---: | :---: | :--- | :--- | :--- | :--- |
| `00000` | `0x00` | **ADD** | R-Type | `ADD Rd, Rs1, Rs2` | `Rd = Rs1 + Rs2` |
| `00001` | `0x01` | **SUB** | R-Type | `SUB Rd, Rs1, Rs2` | `Rd = Rs1 - Rs2` |
| `00010` | `0x02` | **AND** | R-Type | `AND Rd, Rs1, Rs2` | `Rd = Rs1 & Rs2` |
| `00011` | `0x03` | **OR** | R-Type | `OR Rd, Rs1, Rs2` | `Rd = Rs1 \| Rs2` |
| `00100` | `0x04` | **XOR** | R-Type | `XOR Rd, Rs1, Rs2` | `Rd = Rs1 ^ Rs2` |
| `00101` | `0x05` | **SHL** | R-Type | `SHL Rd, Rs1, Rs2` | `Rd = Rs1 << Rs2[2:0]` |
| `00110` | `0x06` | **SHR** | R-Type | `SHR Rd, Rs1, Rs2` | `Rd = Rs1 >> Rs2[2:0]` |
| `00111` | `0x07` | **LDI** | I-Type | `LDI Rd, imm8` | `Rd = imm8` |
| `01000` | `0x08` | **LDD** | ADDI-Type | `LDD Rd, Rs1, imm5` | `Rd = Memory[Rs1 + ZeroExt(imm5)]` |
| `01001` | `0x09` | **STR** | R-Type | `STR Rs1, Rs2, imm5` | `Memory[Rs2 + ZeroExt(imm5)] = Rs1` |
| `01010` | `0x0A` | **JMP** | Branch-Type | `JMP imm8` | `PC = PC + SignExt(imm8)` |
| `01011` | `0x0B` | **JZ** | Branch-Type | `JZ Rs1, imm8` | `if (Rs1 == 0) PC = PC + SignExt(imm8)` |
| `01100` | `0x0C` | **JNZ** | Branch-Type | `JNZ Rs1, imm8` | `if (Rs1 != 0) PC = PC + SignExt(imm8)` |
| `01101` | `0x0D` | **JGT** | Branch-Type | `JGT Rs1, imm8` | `if ($signed(Rs1) > 0) PC = PC + SignExt(imm8)` |
| `01110` | `0x0E` | **ADDI**| ADDI-Type | `ADDI Rd, Rs1, imm5` | `Rd = Rs1 + SignExt(imm5)` |
| `01111` | `0x0F` | **SLT** | R-Type | `SLT Rd, Rs1, Rs2` | `Rd = ($signed(Rs1) < $signed(Rs2)) ? 1 : 0` |
| `10000` | `0x10` | **MUL** | R-Type | `MUL Rd, Rs1, Rs2` | `Rd = (Rs1 * Rs2)[7:0]` |
| `10001` | `0x11` | **MAC** | R-Type | `MAC Rd, Rs1, Rs2` | `Rd = Rd + (Rs1 * Rs2)[7:0]` |
| `10010` | `0x12` | **ROL** | R-Type | `ROL Rd, Rs1, Rs2` | `Rd = RotateLeft(Rs1, Rs2[2:0])` |
| `10011` | `0x13` | **ROR** | R-Type | `ROR Rd, Rs1, Rs2` | `Rd = RotateRight(Rs1, Rs2[2:0])` |
| `10100` | `0x14` | **RETI**| Sys-Type | `RETI` | Return from Hardware Interrupt (`PC = epc`, `in_isr = 0`) |
| `10101` | `0x15` | **STD** | Branch-Type | `STD Rs1, imm8` | `Memory[imm8] = Rs1` |
| `10110` | `0x16` | **JAL** | Branch-Type | `JAL R7, imm8` | `R7 = PC + 1; PC = PC + SignExt(imm8)` |
| `10111` | `0x17` | **JR**  | Sys-Type | `JR Rs1` | `PC = Rs1` (Indirect Jump) |
| `11000` | `0x18` | **TRAP**| Sys-Type | `TRAP` | Trigger Software Exception (`PC = 0x80`, `cause = 3`) |
| `11001` | `0x19` | **ERET**| Sys-Type | `ERET` | Return from Exception (`PC = exception_epc + 1`) |
| `11010` | `0x1A` | **MFC0**| I-Type | `MFC0 Rd, sel` | `Rd = (sel[0] ? exception_epc : exception_cause)` |
| `11111` | `0x1F` | **HALT**| Sys-Type | `HALT` | Freeze CPU execution (`halt = 1`) |

---

## Memory & MMIO Address Map

Data Memory space spans 256 bytes (`0x00` to `0xFF`). Addresses `0xFA` through `0xFF` map to hardware peripherals:

| Address Range | Type | Peripheral / Function | Access Mode |
| :---: | :---: | :--- | :---: |
| `0x00` – `0xF9` | Data RAM | On-chip General Data Memory (250 Bytes) | Read / Write |
| `0xFA` | MMIO | **UART Status Register** (`[7]=overrun, [1]=tx_ready, [0]=rx_valid`) | Read-Only |
| `0xFB` | MMIO | **UART Receiver Data Register** (Read received byte) | Read-Only |
| `0xFC` | MMIO | **UART Transmitter Data Register** (Write byte to transmit) | Write-Only |
| `0xFD` | MMIO | **External ADC Input Pins** (`external_adc_pins`) | Read-Only |
| `0xFE` | MMIO | **External Digital Input Pins** (`external_digital_pins`) | Read-Only |
| `0xFF` | MMIO | **PWM Generator Duty Cycle** (`motor_pwm_pin`) | Read / Write |

---

## Exception & Interrupt Architecture

- **Vector Address:** `0x80`
- **Causes (`exception_cause`):**
  - `1`: ALU Arithmetic Overflow (`ADD` / `ADDI` signed overflow or unsigned wrap)
  - `2`: Illegal Instruction (Undefined Opcode in Decode stage)
  - `3`: Software Trap (`TRAP` instruction)
  - **Hardware Interrupt:** Triggered by rising edge on external `interrupt_pin`. Saves PC to `epc` and branches to `0x80`. Returning is handled via `RETI`.
