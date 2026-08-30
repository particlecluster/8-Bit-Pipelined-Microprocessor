# 16-bit Pipelined Microprocessor — Instruction Set Architecture (ISA)

## Architecture Summary

| Parameter | Value |
|:--|:--|
| **Instruction Width** | 16 bits |
| **Data Path Width** | 8 bits |
| **Address Bus Width** | 8 bits (256-byte address space) |
| **General Purpose Registers** | 8 × 8-bit (`R0`–`R7`) |
| **Pipeline Stages** | 5 (IF → ID → EX → MEM → WB) |
| **Branch Predictor** | 32-entry BTB + 32-entry BHT (1-bit) |
| **Exception Vector** | `0x80` |

### Register File

| Register | Purpose |
|:--|:--|
| `R0` | Hardwired to `0x00` (writes ignored, reads always return `0`) |
| `R1`–`R5` | General purpose |
| `R6` | General purpose / Stack pointer (by convention) |
| `R7` | Link register (return address for `JAL`) |

### Special Registers (CP0 Coprocessor)

| Register | Description |
|:--|:--|
| `exception_epc` | Exception program counter (faulting instruction address) |
| `exception_cause` | Exception cause code (`1` = Overflow, `2` = Illegal, `3` = Trap) |
| `epc` | Hardware interrupt return address |

---

## Instruction Formats

All instructions are 16 bits wide. The opcode occupies bits `[15:11]`.

### 1. R-Type (Register)

Used for arithmetic, logic, shift, rotate, compare, multiply, and MAC operations.

```
 15        11 10      8  7       5  4       2  1  0
┌───────────┬──────────┬──────────┬──────────┬─────┐
│  Opcode   │    Rd    │   Rs1    │   Rs2    │  -- │
│  (5 bit)  │  (3 bit) │  (3 bit) │  (3 bit) │(2b) │
└───────────┴──────────┴──────────┴──────────┴─────┘
```

> **Note:** For `MAC`, `Rd` is also read as the accumulator source via a dedicated 3rd read port (`rs3`).
> For `STR`, `Rd` holds the **source data** register to store.

### 2. I-Type — 8-bit Immediate

Used for `LDI`, `STD`, and `MFC0`.

```
 15        11 10      8  7                        0
┌───────────┬──────────┬───────────────────────────┐
│  Opcode   │    Rd    │     8-bit Immediate       │
│  (5 bit)  │  (3 bit) │         (8 bit)           │
└───────────┴──────────┴───────────────────────────┘
```

### 3. I-Type — 5-bit Immediate (ADDI / Indexed Memory)

Used for `ADDI`, `LDD`, and `STR`.

```
 15        11 10      8  7       5  4             0
┌───────────┬──────────┬──────────┬────────────────┐
│  Opcode   │    Rd    │   Rs1    │   5-bit Imm    │
│  (5 bit)  │  (3 bit) │  (3 bit) │    (5 bit)     │
└───────────┴──────────┴──────────┴────────────────┘
```

> **Immediate extension:** `ADDI` uses **sign-extended** `imm5`. `LDD` and `STR` use **zero-extended** `imm5`.

### 4. Branch-Type (PC-Relative)

Used for `JMP`, `JZ`, `JNZ`, `JGT`, `JAL`, and `STD`.

```
 15        11 10      8  7                        0
┌───────────┬──────────┬───────────────────────────┐
│  Opcode   │  Rd/Rs1  │   8-bit Offset / Addr     │
│  (5 bit)  │  (3 bit) │         (8 bit)           │
└───────────┴──────────┴───────────────────────────┘
```

> **Branch target:** `PC + SignExt(imm8)`. For `JAL`: `R[rd] = PC + 1` before branching.

### 5. System-Type

Used for `JR`, `TRAP`, `ERET`, `RETI`, `HALT`.

```
 15        11 10      8  7                        0
┌───────────┬──────────┬───────────────────────────┐
│  Opcode   │  Rd/Rs1  │        Unused             │
│  (5 bit)  │  (3 bit) │         (8 bit)           │
└───────────┴──────────┴───────────────────────────┘
```

> **`JR`:** Target = `R[rd]`. Other system instructions ignore the register and immediate fields.

---

## Complete Instruction Table (28 Instructions)

### Arithmetic & Logic

| Opcode | Hex | Mnemonic | Format | Syntax | Operation |
|:---:|:---:|:---|:---|:---|:---|
| `00000` | `0x00` | **ADD** | R | `ADD Rd, Rs1, Rs2` | `Rd = Rs1 + Rs2` |
| `00001` | `0x01` | **SUB** | R | `SUB Rd, Rs1, Rs2` | `Rd = Rs1 - Rs2` |
| `00010` | `0x02` | **AND** | R | `AND Rd, Rs1, Rs2` | `Rd = Rs1 & Rs2` |
| `00011` | `0x03` | **OR**  | R | `OR Rd, Rs1, Rs2`  | `Rd = Rs1 \| Rs2` |
| `00100` | `0x04` | **XOR** | R | `XOR Rd, Rs1, Rs2` | `Rd = Rs1 ^ Rs2` |
| `01110` | `0x0E` | **ADDI**| I-5 | `ADDI Rd, Rs1, imm5` | `Rd = Rs1 + SignExt(imm5)` |
| `01111` | `0x0F` | **SLT** | R | `SLT Rd, Rs1, Rs2` | `Rd = ($signed(Rs1) < $signed(Rs2)) ? 1 : 0` |

### Shift & Rotate

| Opcode | Hex | Mnemonic | Format | Syntax | Operation |
|:---:|:---:|:---|:---|:---|:---|
| `00101` | `0x05` | **SHL** | R | `SHL Rd, Rs1, Rs2` | `Rd = Rs1 << Rs2[2:0]` |
| `00110` | `0x06` | **SHR** | R | `SHR Rd, Rs1, Rs2` | `Rd = Rs1 >> Rs2[2:0]` |
| `10010` | `0x12` | **ROL** | R | `ROL Rd, Rs1, Rs2` | `Rd = RotateLeft(Rs1, Rs2[2:0])` |
| `10011` | `0x13` | **ROR** | R | `ROR Rd, Rs1, Rs2` | `Rd = RotateRight(Rs1, Rs2[2:0])` |

### Multiply & Accumulate

| Opcode | Hex | Mnemonic | Format | Syntax | Operation |
|:---:|:---:|:---|:---|:---|:---|
| `10000` | `0x10` | **MUL** | R | `MUL Rd, Rs1, Rs2` | `Rd = (Rs1 * Rs2)[7:0]` |
| `10001` | `0x11` | **MAC** | R | `MAC Rd, Rs1, Rs2` | `Rd = Rd + (Rs1 * Rs2)[7:0]` |

### Load & Store

| Opcode | Hex | Mnemonic | Format | Syntax | Operation |
|:---:|:---:|:---|:---|:---|:---|
| `00111` | `0x07` | **LDI** | I-8 | `LDI Rd, imm8` | `Rd = imm8` |
| `01000` | `0x08` | **LDD** | I-5 | `LDD Rd, Rs1, imm5` | `Rd = Mem[Rs1 + ZeroExt(imm5)]` |
| `01001` | `0x09` | **STR** | I-5 | `STR Rd, Rs1, imm5` | `Mem[Rs1 + ZeroExt(imm5)] = Rd` |
| `10101` | `0x15` | **STD** | I-8 | `STD Rs1, imm8` | `Mem[imm8] = Rs1` |

### Branch & Jump

| Opcode | Hex | Mnemonic | Format | Syntax | Operation |
|:---:|:---:|:---|:---|:---|:---|
| `01010` | `0x0A` | **JMP** | Branch | `JMP imm8` | `PC = PC + SignExt(imm8)` |
| `01011` | `0x0B` | **JZ**  | Branch | `JZ Rs1, imm8` | `if (Rs1 == 0) PC += SignExt(imm8)` |
| `01100` | `0x0C` | **JNZ** | Branch | `JNZ Rs1, imm8` | `if (Rs1 != 0) PC += SignExt(imm8)` |
| `01101` | `0x0D` | **JGT** | Branch | `JGT Rs1, imm8` | `if ($signed(Rs1) > 0) PC += SignExt(imm8)` |
| `10110` | `0x16` | **JAL** | Branch | `JAL Rd, imm8` | `Rd = PC + 1; PC += SignExt(imm8)` |
| `10111` | `0x17` | **JR**  | System | `JR Rs1` | `PC = Rs1` |

### System & Exception

| Opcode | Hex | Mnemonic | Format | Syntax | Operation |
|:---:|:---:|:---|:---|:---|:---|
| `10100` | `0x14` | **RETI** | System | `RETI` | Return from interrupt: `PC = epc`, clear `in_isr` |
| `11000` | `0x18` | **TRAP** | System | `TRAP` | Software trap → `PC = 0x80`, `cause = 3` |
| `11001` | `0x19` | **ERET** | System | `ERET` | Exception return: `PC = exception_epc + 1`, clear `in_exception` |
| `11010` | `0x1A` | **MFC0** | I-8 | `MFC0 Rd, sel` | `Rd = (sel[0]) ? exception_epc : exception_cause` |
| `11111` | `0x1F` | **HALT** | System | `HALT` | Freeze CPU execution |

> **Invalid opcodes** (`0x1B`–`0x1E`) trigger an **Illegal Instruction Exception** (`cause = 2`).

---

## Memory-Mapped I/O (MMIO) Address Map

| Address | Access | Peripheral | Description |
|:---:|:---:|:---|:---|
| `0x00`–`0xF2` | R/W | **Data RAM** | General-purpose SRAM (243 bytes) |
| `0xF3` | R/W | **Accelerometer Y** | MPU-6050 `ACCEL_YOUT_H` — signed 8-bit Y-axis |
| `0xF4` | R/W | **Accelerometer X** | MPU-6050 `ACCEL_XOUT_H` — signed 8-bit X-axis |
| `0xF5`–`0xF6` | R/W | **Data RAM** | General-purpose SRAM |
| `0xF7` | R | **I²C Status** | I2C engine status flags (read-only) |
| `0xF8` | R | **I²C RX Data** | Byte received from I2C slave (read-only) |
| `0xF9` | R/W | **Data RAM** | General-purpose SRAM |
| `0xFA` | R | **UART Status** | `[0]` = TX busy, `[1]` = RX ready (read-only) |
| `0xFB` | R | **UART RX Data** | Read received byte; auto-pops RX FIFO |
| `0xFC` | W | **UART TX Data** | Write byte to transmit; strobes TX start |
| `0xFD` | R | **ADC Input** | External 8-bit analog input (`external_adc_pins`) |
| `0xFE` | R | **Digital Input** | External 8-bit GPIO input (`external_digital_pins`) |
| `0xFF` | R/W | **PWM Duty Cycle** | 8-bit duty cycle for hardware PWM generator |

> **Note:** The I²C Command Register, Slave Address, and Register Address are controlled through the I²C peripheral module via `0xF5`–`0xF8` in the top-level `design.v` integration, where additional MMIO decoding maps `0xF5` (I2C Command), `0xF6` (I2C Status), `0xF7` (I2C Slave Addr), `0xF8` (I2C Reg Addr), `0xF9` (I2C Write Data), and `0xFA` (I2C Read Data) to the I2C engine. See `design.v` for the full top-level MMIO routing.

---

## Exception & Interrupt Architecture

### Exception Causes

| Code | Name | Trigger |
|:---:|:---|:---|
| `1` | **Overflow** | Signed overflow on `ADD` / `ADDI` in EX stage |
| `2` | **Illegal Instruction** | Invalid opcode decoded in ID stage |
| `3` | **Software Trap** | `TRAP` instruction executed in ID stage |

### Behavior

| Event | EPC Saved | Return Instruction | Return Target |
|:---|:---|:---|:---|
| Hardware interrupt | `epc = PC` | `RETI` | `PC = epc` |
| Overflow exception | `exception_epc = ex_pc` | `ERET` | `PC = exception_epc + 1` |
| Illegal / Trap | `exception_epc = if_pc` | `ERET` | `PC = exception_epc + 1` |

- **Vector address:** `0x80` (all exceptions and interrupts jump here)
- Hardware interrupts are triggered by a rising edge on the external `interrupt_pin`
- Nested exceptions are blocked while `in_exception` or `in_isr` is set

---

## Pipeline Hazard Resolution

### Data Forwarding (`fwd_unit.v`)

Three forwarding paths (`fwd_rd1`, `fwd_rd2`, `fwd_rd3`) with priority:

1. **EX/MEM → EX** (highest priority): Forward ALU result from the instruction in MEM stage
2. **MEM/WB → EX**: Forward write-back data from the instruction in WB stage

> Forwarding is disabled when the source is a load instruction (`res_src == 2'b01`) — this triggers a **load-use stall** instead.

### Load-Use Stall

When an instruction in ID depends on a `LDD` in EX:
- IF and ID stages are **stalled** for 1 cycle
- A **bubble** (NOP) is inserted into EX

### Branch Prediction (`branch_pred.v`)

- **32-entry BTB** indexed by `PC[4:0]`, stores 8-bit PC tag + 8-bit target
- **32-entry BHT** with 1-bit taken/not-taken predictor
- Predictions made for: `JMP`, `JZ`, `JNZ`, `JGT`, `JAL`
- On misprediction: flush IF/ID and ID/EX pipeline registers, redirect PC
- `JR`, `RETI`, `ERET` resolved in EX stage with pipeline flush
