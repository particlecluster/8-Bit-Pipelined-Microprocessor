# 5-Stage Pipelined 8-Bit CPU — IMU-Driven LED Matrix SoC

**Team Voltere | IIT Indore | IITISoC 2026**

A synthesizable System-on-Chip (SoC) built entirely in Verilog, featuring a custom 5-stage pipelined 8-bit RISC microprocessor that communicates with an MPU-6050 IMU sensor over I2C and drives an 8×8 LED matrix display with real-time fluid physics rendering.

The microprocessor initializes and continuously polls the IMU sensor over I²C, routing signed 8-bit acceleration data through the CPU's memory-mapped I/O bus to a dedicated hardware LED Matrix Controller. The controller runs a **hardware auto-calibration sequence on every reset** to eliminate IMU zero-g bias, then renders a **3×3 viscous water droplet** that physically flows across the matrix in response to board tilt — simulating liquid momentum, viscous drag, fluid elongation, and wall-impact splashing.

---

## 📐 Microarchitecture Overview

```text
       +---------+     +---------+     +---------+     +---------+     +---------+
       |   IF    | --> |   ID    | --> |   EX    | --> |   MEM   | --> |   WB    |
       |  Fetch  |     | Decode  |     | Execute |     | Memory  |     |Write-Back|
       +---------+     +---------+     +---------+     +---------+     +---------+
            |               |               |               |               |
        [u_PC / IMEM]   [u_RegFile]     [u_ALU / BRU]   [u_DMEM / UART]  [Write Mux]
        [u_BP (BTB)]   [Load-Use Hazard] [u_FWD / CP0]   [u_I2C / MMIO]
```

<a href="docs/arch.svg" target="_blank">
  <img src="docs/arch.svg" alt="CPU Architecture" width="100%">
</a>

### Key Architectural Specifications

| Parameter | Value |
| :--- | :--- |
| **Instruction Width** | 16 bits |
| **Data Bus Width** | 8 bits |
| **Address Space** | 256 bytes (8-bit byte-addressed) |
| **Register File** | 8 × 8-bit (`R0`–`R7`); `R0` hardwired to `0`; `R7` = Link Register |
| **Pipeline Stages** | 5 (IF → ID → EX → MEM → WB) |
| **Operating Frequency** | **25 MHz** (derived from 100 MHz onboard oscillator via `clk_wiz_0`) |
| **I2C Bus Frequency** | **100 kHz** SCL (Standard Mode) |
| **Matrix Scan Rate** | **1 kHz** per column (8 columns → **125 Hz** full-frame refresh) |
| **UART Baud Rate** | **115,200 baud** |

---

## 🏗️ System Architecture: Hardware/Software Co-Design

This project is a **Hardware/Software Co-Design** — complex tasks are split between the CPU (software) and dedicated hardware accelerators (Verilog modules):

```
  ┌────────────────────────────────────────────────────────────────────────┐
  │                         SOFTWARE DOMAIN (CPU)                          │
  │  • Initializes MPU-6050 I2C registers on boot                         │
  │  • Runs continuous polling loop to read accel_x / accel_y bytes       │
  │  • Routes sensor data to MMIO addresses 0xF4 and 0xF3                 │
  └──────────────────────────────────┬─────────────────────────────────────┘
                                     │ Memory-Mapped I/O Bus
                                     ▼
  ┌────────────────────────────────────────────────────────────────────────┐
  │                       HARDWARE DOMAIN (FPGA)                           │
  │  • I2C Engine: bit-bangs 100 kHz SCL/SDA protocol at cycle precision  │
  │  • LED Controller: 2-stage EMA DSP filter + Schmitt hysteresis        │
  │  • 1 kHz column multiplexer drives the physical 8×8 LED matrix        │
  └────────────────────────────────────────────────────────────────────────┘
```

---

## 💾 `program.hex.txt` — CPU Firmware (Machine Code)

The file [`program.hex.txt`](program.hex.txt) contains the **complete CPU firmware** stored as 16-bit hexadecimal instruction words — one word per line — loaded directly into the synthesized Instruction ROM on the FPGA.

The program is hand-assembled using the custom ISA and performs the following execution sequence:

### Phase 1: MPU-6050 Initialization (Boot Sequence)
On reset, the CPU writes to the following sensor registers over I2C to bring the MPU-6050 out of sleep mode:

| Step | I2C Register | Value Written | Effect |
| :---: | :--- | :---: | :--- |
| 1 | `PWR_MGMT_1` (`0x6B`) | `0x00` | Wake sensor from sleep mode |
| 2 | `SMPLRT_DIV` (`0x19`) | `0x07` | Set internal sample rate to 1 kHz |
| 3 | `CONFIG` (`0x1A`) | `0x03` | Enable 44 Hz hardware DLPF (Digital Low-Pass Filter) |
| 4 | `ACCEL_CONFIG` (`0x1C`) | `0x00` | Set accelerometer full-scale range to ±2g (64 LSB/g) |

### Phase 2: Continuous Sensor Polling Loop (Infinite)
After initialization, the CPU enters an infinite loop:

```
 1. Write I2C slave address 0x68 to MMIO 0xF7
 2. Write register pointer 0x3B (ACCEL_XOUT_H) to MMIO 0xF8
 3. Write READ command to I2C Command Register (0xF5)
 4. Poll MMIO 0xF6 (I2C Status) until BUSY bit == 0   ← Polling Protocol
 5. Read received byte from MMIO 0xFA
 6. Store accel_x byte to MMIO 0xF4
 7. Repeat steps 1–6 for 0x3D (ACCEL_YOUT_H) → stored at MMIO 0xF3
 8. Jump back to step 1 (infinite loop)
```

> **Polling Protocol**: The CPU repeatedly reads the I2C Status Register (`0xF6`) in a tight loop, waiting until the hardware I2C engine clears the BUSY bit. This synchronizes the software polling rate (~kHz) with the hardware I2C bus timing (100 kHz), ensuring no bytes are dropped without requiring interrupt hardware.

The data stored at `0xF4` and `0xF3` is then continuously read by the hardware `LED_Matrix_Controller` module as live wires, requiring no further CPU involvement for the display.

---

## 🌊 LED Matrix Controller — 3×3 Viscous Water Droplet + Auto-Calibration

The [`src/led_matrix_controller.v`](src/led_matrix_controller.v) module implements a **real-time fluid physics engine** for the 1588BS 8×8 LED matrix. It renders a **3×3 viscous water droplet** (9 lit pixels) that physically flows in response to board tilt, with hardware auto-calibration on every reset to eliminate IMU zero-g offset bias.

> **Note:** The module comment header references "2×2 Dot Spirit Level" — this is a legacy comment from an earlier revision. The current active build is the 3×3 fluid drop engine with auto-calibration.

### Startup Auto-Calibration (Press RESET — Keep Board Flat)

On every reset, before fluid simulation begins, the hardware runs a **1.2-second auto-calibration loop** directly inside the FPGA:

```
  Phase 1 (0–200 ms):    Sensor wake-up settling period
                         → Matrix displays blinking 2×2 center dot

  Phase 2 (200–1224 ms): Accumulates 64 IMU samples (1 every 16 ms)
                         → Matrix displays blinking outer target ring

  Phase 3 (> 1224 ms):   Computes bias_x = avg(accel_x), bias_y = avg(accel_y)
                         → Locks offsets, starts fluid simulation
```

> ⚠️ **Keep the board completely flat during the first 1.2 seconds after pressing RESET.** The calibration learns the resting zero-g bias so the droplet sits dead-center when flat.

After calibration, all sensor readings are corrected:
$$\text{corrected\_ax} = \text{raw\_ax} - \text{bias\_x}$$
$$\text{corrected\_ay} = \text{raw\_ay} - \text{bias\_y}$$

### Signal Processing Pipeline

```
  Raw IMU Byte (accel_x / accel_y, signed 8-bit, 64 LSB/g at ±2g)
                          │
                          ▼
  ┌─────────────────────────────────────────────────────┐
  │  Hardware Auto-Calibration (1.2 s, runs on reset)   │  64-sample average → bias_x, bias_y
  └─────────────────────┬───────────────────────────────┘
                        ▼  corrected = raw - bias
  ┌─────────────────────────────────────────────────────┐
  │  Stage 1: 64-Sample Q8.8 Fixed-Point EMA Filter     │  Strips sensor quantization & spikes
  │  y₁[n] = y₁[n-1] + ((x[n] - y₁[n-1]) >> 6)        │  α = 1/64
  └─────────────────────┬───────────────────────────────┘
                        ▼
  ┌─────────────────────────────────────────────────────┐
  │  Stage 2: 32-Sample Q8.8 Fixed-Point EMA Filter     │  2nd-order smooth analog roll-off
  │  y₂[n] = y₂[n-1] + ((y₁[n] - y₂[n-1]) >> 5)       │  α = 1/32 → silky fluid feel
  └─────────────────────┬───────────────────────────────┘
                        ▼
  ┌─────────────────────────────────────────────────────┐
  │  Sub-Pixel Q8.8 Fluid Kinematics (50 Hz / 20 ms)   │  Gravity accel + viscous drag
  │  vel += gravity; vel *= 0.844 (drag); pos += vel    │  Resting velocity zero-clamped
  └─────────────────────┬───────────────────────────────┘
                        ▼
  ┌─────────────────────────────────────────────────────┐
  │  Shape Renderer: 3×3 Core + Fluid Tail + Splashes  │  Dynamic deformation on impact
  └─────────────────────┬───────────────────────────────┘
                        ▼
  ┌─────────────────────────────────────────────────────┐
  │  1 kHz Column Multiplexer + Registered Output Drive │  Glitch-free, flicker-free display
  │  Active HIGH Anodes (cols) / Active LOW Cathodes    │  125 Hz full frame refresh rate
  └─────────────────────────────────────────────────────┘
```

### Fluid Drop Behavior

| Condition | Behavior |
| :--- | :--- |
| **Flat on table (post-calibration)** | Drop locked dead-center (Rows 2–4, Cols 2–4), zero jitter |
| **Gentle tilt** | Drop slowly accelerates and rolls with viscous fluid drag |
| **Steep tilt** | Drop rushes across the matrix; elongates into a trailing stream tail |
| **Wall impact** | Drop flattens into a 5–7 pixel wide splash film along the border, then pulls back into 3×3 blob |
| **Diagonal tilt** | Drop flows toward corners with correct 2D momentum composition |
| **Return to flat** | Viscous drag decelerates and re-centers the drop smoothly |

---

## 🔌 Hardware Setup

### Target Platform

| Component | Part Number / Model | Notes |
| :--- | :--- | :--- |
| **FPGA Board** | Digilent Arty A7-35T | Xilinx Artix-7 `XC7A35TCSG324-1` |
| **IMU Sensor** | InvenSense MPU-6050 | 6-DOF, connected via I²C (3.3V logic) |
| **LED Matrix** | 1588BS 8×8 Common-Cathode | Driven via PMOD JC (rows) + PMOD JD (cols) |

### Clock Frequency Summary

| Clock Domain | Frequency | Source |
| :--- | :---: | :--- |
| **Onboard Crystal Oscillator** | 100 MHz | Arty A7 onboard crystal (`E3`) |
| **CPU / System Clock** | **25 MHz** | `clk_wiz_0` PLL divider from 100 MHz |
| **I2C SCL (Sensor Bus)** | **100 kHz** | I2C engine clocked from 25 MHz system clock |
| **Matrix Column Scan Rate** | **1 kHz** | 25,000 system cycles per column |
| **Matrix Frame Refresh Rate** | **125 Hz** | 8 columns × 1 kHz scan |
| **Physics Engine Update Rate** | **50 Hz** (20 ms) | Fluid kinematics simulation tick |
| **UART Baud Rate** | **115,200 baud** | TX/RX peripheral |

### MPU-6050 IMU Wiring (I²C)

| MPU-6050 Pin | FPGA Pin | Signal | Notes |
| :---: | :---: | :--- | :--- |
| `VCC` | `3.3V` | Power | 3.3V from Arty A7 PMOD rail |
| `GND` | `GND` | Ground | Common ground |
| `SCL` | `L18` | `i2c_scl` | 100 kHz I²C Clock |
| `SDA` | `M18` | `i2c_sda` | I²C Bidirectional Data |
| `AD0` | `GND` | I²C Address LSB | Pulls address to `0x68` |
| `INT` | *(NC)* | Interrupt | Not used (polling mode) |

> **I²C Slave Address:** `0x68` (AD0 pulled LOW)

### Onboard LED Tilt Indicators (Arty A7 Green LEDs)

The four green onboard LEDs give a directional tilt readout simultaneously with the matrix:

| LED | Silkscreen | FPGA Pin | Tilt Direction |
| :---: | :---: | :---: | :--- |
| `led_out[3]` | `LD7` | `T10` | Forward (board tilted away from you) |
| `led_out[2]` | `LD6` | `T9` | Backward (board tilted toward you) |
| `led_out[1]` | `LD5` | `J5` | Right tilt |
| `led_out[0]` | `LD4` | `H5` | Left tilt |

### 1588BS 8×8 LED Matrix — Row Connections (PMOD JC)

> Rows are driven as **Active LOW Cathodes** — a driven row pin goes LOW to enable that row.

| Signal | FPGA Pin | PMOD JC Header Pin | 1588BS Matrix Pin | Row |
| :--- | :---: | :---: | :---: | :--- |
| `matrix_rows[0]` | `U12` | Pin 1 | Pin 9 | Row 0 (Top) |
| `matrix_rows[1]` | `V12` | Pin 2 | Pin 14 | Row 1 |
| `matrix_rows[2]` | `V10` | Pin 3 | Pin 8 | Row 2 |
| `matrix_rows[3]` | `V11` | Pin 4 | Pin 12 | Row 3 |
| `matrix_rows[4]` | `U14` | Pin 7 | Pin 1 | Row 4 |
| `matrix_rows[5]` | `V14` | Pin 8 | Pin 7 | Row 5 |
| `matrix_rows[6]` | `T13` | Pin 9 | Pin 2 | Row 6 |
| `matrix_rows[7]` | `U13` | Pin 10 | Pin 5 | Row 7 (Bottom) |

### 1588BS 8×8 LED Matrix — Column Connections (PMOD JD)

> Columns are driven as **Active HIGH Anodes** — a driven column pin goes HIGH to enable that column.

| Signal | FPGA Pin | PMOD JD Header Pin | 1588BS Matrix Pin | Column |
| :--- | :---: | :---: | :---: | :--- |
| `matrix_cols[0]` | `D4` | Pin 1 | Pin 13 | Col 0 (Left) |
| `matrix_cols[1]` | `D3` | Pin 2 | Pin 3 | Col 1 |
| `matrix_cols[2]` | `F4` | Pin 3 | Pin 4 | Col 2 |
| `matrix_cols[3]` | `F3` | Pin 4 | Pin 10 | Col 3 |
| `matrix_cols[4]` | `E2` | Pin 7 | Pin 6 | Col 4 |
| `matrix_cols[5]` | `D2` | Pin 8 | Pin 11 | Col 5 |
| `matrix_cols[6]` | `H2` | Pin 9 | Pin 15 | Col 6 |
| `matrix_cols[7]` | `G2` | Pin 10 | Pin 16 | Col 7 (Right) |

> ⚠️ **Critical Polarity Warning:** Inactive columns **must** be driven LOW and inactive rows **must** be driven HIGH. Reversing this polarity will forward-bias all 64 LEDs simultaneously, turning on the entire matrix.

---

## 🗺️ Memory-Mapped I/O (MMIO) Address Map

| Address | Peripheral / Register | Access | Notes |
| :---: | :--- | :---: | :--- |
| `0x00` – `0xDF` | General Purpose Data RAM (224 bytes) | R/W | Internal SRAM |
| `0xF0` | UART TX Data Register | W | Write byte to transmit |
| `0xF1` | UART Status Register | R | Bit 0 = TX Busy, Bit 1 = RX Valid |
| `0xF2` | UART RX Data Register | R | Received byte |
| `0xF3` | **Accelerometer Y-Axis (`accel_y`)** | R/W | Signed byte from MPU-6050 ACCEL_YOUT_H |
| `0xF4` | **Accelerometer X-Axis (`accel_x`)** | R/W | Signed byte from MPU-6050 ACCEL_XOUT_H |
| `0xF5` | I2C Command Register | W | `0x01` = Read, `0x02` = Write |
| `0xF6` | I2C Status Register | R | Bit 0 = BUSY, Bit 1 = NACK Error |
| `0xF7` | I2C Slave Address | W | `0x68` for MPU-6050 |
| `0xF8` | I2C Register Address Pointer | W | Target sensor register address |
| `0xF9` | I2C Write Data Payload | W | Byte to write to sensor |
| `0xFA` | I2C Read Data Payload | R | Byte received from sensor |
| `0xFC` | GPIO LED Output | W | General purpose LED control |
| `0xFD` | GPIO Switch / Button Inputs | R | Onboard switch states |

---

## 📜 Instruction Set Architecture (ISA)

Instructions are 16-bit words encoded in 5 primary formats (Opcode = `inst[15:11]`):

```text
1. R-Type (Register):   | Opcode (5) | Rd (3) | Rs1 (3) | Rs2 (3) | Unused (2) |
2. I-Type (Immediate):  | Opcode (5) | Rd (3) | Immediate (8)                  |
3. ADDI-Type (Offset):  | Opcode (5) | Rd (3) | Rs1 (3) | Imm5 (5)             |
4. Branch / Direct:     | Opcode (5) | Rs1 (3)| Immediate / Target Address (8)  |
5. System / Indirect:   | Opcode (5) | Rs1 (3)| Unused (8)                     |
```

### Full Instruction Table (28 Instructions)

| Opcode | Hex | Mnemonic | Format | Syntax | Operation |
| :---: | :---: | :--- | :--- | :--- | :--- |
| `00000` | `0x00` | **ADD** | R | `ADD Rd, Rs1, Rs2` | `Rd = Rs1 + Rs2` |
| `00001` | `0x01` | **SUB** | R | `SUB Rd, Rs1, Rs2` | `Rd = Rs1 - Rs2` |
| `00010` | `0x02` | **AND** | R | `AND Rd, Rs1, Rs2` | `Rd = Rs1 & Rs2` |
| `00011` | `0x03` | **OR** | R | `OR Rd, Rs1, Rs2` | `Rd = Rs1 \| Rs2` |
| `00100` | `0x04` | **XOR** | R | `XOR Rd, Rs1, Rs2` | `Rd = Rs1 ^ Rs2` |
| `00101` | `0x05` | **SHL** | R | `SHL Rd, Rs1, Rs2` | `Rd = Rs1 << Rs2[2:0]` |
| `00110` | `0x06` | **SHR** | R | `SHR Rd, Rs1, Rs2` | `Rd = Rs1 >> Rs2[2:0]` |
| `00111` | `0x07` | **LDI** | I | `LDI Rd, imm8` | `Rd = imm8` |
| `01000` | `0x08` | **LDD** | ADDI | `LDD Rd, Rs1, imm5` | `Rd = Mem[Rs1 + ZeroExt(imm5)]` |
| `01001` | `0x09` | **STR** | R | `STR Rs1, Rs2, imm5` | `Mem[Rs2 + ZeroExt(imm5)] = Rs1` |
| `01010` | `0x0A` | **JMP** | Branch | `JMP imm8` | `PC = PC + SignExt(imm8)` |
| `01011` | `0x0B` | **JZ** | Branch | `JZ Rs1, imm8` | `if (Rs1 == 0) PC += SignExt(imm8)` |
| `01100` | `0x0C` | **JNZ** | Branch | `JNZ Rs1, imm8` | `if (Rs1 != 0) PC += SignExt(imm8)` |
| `01101` | `0x0D` | **JGT** | Branch | `JGT Rs1, imm8` | `if (signed Rs1 > 0) PC += SignExt(imm8)` |
| `01110` | `0x0E` | **ADDI** | ADDI | `ADDI Rd, Rs1, imm5` | `Rd = Rs1 + SignExt(imm5)` |
| `01111` | `0x0F` | **SLT** | R | `SLT Rd, Rs1, Rs2` | `Rd = (Rs1 < Rs2) ? 1 : 0` (signed) |
| `10000` | `0x10` | **MUL** | R | `MUL Rd, Rs1, Rs2` | `Rd = (Rs1 * Rs2)[7:0]` |
| `10001` | `0x11` | **MAC** | R | `MAC Rd, Rs1, Rs2` | `Rd = Rd + (Rs1 * Rs2)[7:0]` |
| `10010` | `0x12` | **ROL** | R | `ROL Rd, Rs1, Rs2` | `Rd = RotateLeft(Rs1, Rs2[2:0])` |
| `10011` | `0x13` | **ROR** | R | `ROR Rd, Rs1, Rs2` | `Rd = RotateRight(Rs1, Rs2[2:0])` |
| `10100` | `0x14` | **RETI** | System | `RETI` | Return from interrupt (`PC = epc`) |
| `10101` | `0x15` | **STD** | Branch | `STD Rs1, imm8` | `Mem[imm8] = Rs1` |
| `10110` | `0x16` | **JAL** | Branch | `JAL R7, imm8` | `R7 = PC+1; PC += SignExt(imm8)` |
| `10111` | `0x17` | **JR** | System | `JR Rs1` | `PC = Rs1` (indirect jump) |
| `11000` | `0x18` | **TRAP** | System | `TRAP` | Software trap → `PC = 0x80` |
| `11001` | `0x19` | **ERET** | System | `ERET` | Return from exception |
| `11010` | `0x1A` | **MFC0** | I | `MFC0 Rd, sel` | `Rd = CP0[sel]` (epc or cause) |
| `11111` | `0x1F` | **HALT** | System | `HALT` | Freeze CPU execution |

For complete encoding details, see [`docs/ISA_specification.md`](docs/ISA_specification.md).

---

## ⚙️ Pipeline Hazard Resolution

1. **Data Forwarding Unit (`u_FWD`):**
   - **EX→EX:** Forwards ALU results directly to the next instruction's operands with zero stalls.
   - **MEM→EX:** Forwards write-back data to EX stage operands without stalling.

2. **Load-Use Hazard Stalling:**
   - Detected when an instruction in Decode depends on a `LDD` in Execute.
   - Automatically stalls IF/ID and PC by one cycle, inserting a pipeline bubble.

3. **Branch Prediction & Flush (`u_BP` + `u_BRU`):**
   - 32-entry BTB + 32-entry BHT predicts branch targets at Fetch.
   - On misprediction, flushes `IF_ID` and `ID_EX` and redirects PC to the correct target.

4. **CP0 Exception Processing (`u_CP0`):**
   - Exception vector address: `0x80`
   - `exception_cause`: `1` = Overflow, `2` = Illegal Instruction, `3` = Software Trap
   - `MFC0` reads CP0 registers; `ERET` cleanly returns from exception context.

---

## 🧪 Verification Suite

Self-checking testbenches located in [`sim/comprehensive_test/`](sim/comprehensive_test/):

| Testbench | Coverage | Status |
| :--- | :--- | :---: |
| `tb_isa_instructions.v` | All 28 ISA instructions | ✅ PASSED |
| `tb_hazards_forwarding.v` | EX→EX, MEM→EX forwarding, Load-Use stalls | ✅ PASSED |
| `tb_branch_prediction.v` | BTB/BHT hits/misses, JAL/JR, mispredict flushes | ✅ PASSED |
| `tb_exceptions_interrupts.v` | Overflow, Illegal, TRAP, MFC0, ERET, RETI | ✅ PASSED |
| `tb_peripherals_uart.v` | GPIO, ADC, PWM, UART TX | ✅ PASSED |
| `tb_uart_full_loopback.v` | Hardware UART TX→RX loopback at 115,200 baud | ✅ PASSED |
| `tb_master_suite.v` | Integrated system-level verification | ✅ PASSED |
| `sim/tb_cpu_i2c.v` | Full CPU + I2C + MPU-6050 mock slave co-simulation | ✅ PASSED |

### Running Testbenches (Icarus Verilog)

```powershell
# 1. Master Verification Suite (Full Pipelined System)
iverilog -I src -o sim_test src/*.v sim/comprehensive_test/tb_master_suite.v ; vvp sim_test

# 2. CPU + I2C + MPU-6050 Co-Simulation
iverilog -o sim_test design.v src/i2c_peripheral.v src/led_matrix_controller.v sim/tb_cpu_i2c.v ; vvp sim_test

# 3. ISA Instruction Verification Suite
iverilog -I src -o sim_test src/*.v sim/comprehensive_test/tb_isa_instructions.v ; vvp sim_test

# 4. Data Hazards & Forwarding Suite
iverilog -I src -o sim_test src/*.v sim/comprehensive_test/tb_hazards_forwarding.v ; vvp sim_test

# 5. Branch Prediction & Flush Suite
iverilog -I src -o sim_test src/*.v sim/comprehensive_test/tb_branch_prediction.v ; vvp sim_test

# 6. Hardware UART Serial Loopback Verification (115,200 baud)
iverilog -I src -o sim_test src/*.v sim/comprehensive_test/tb_uart_full_loopback.v ; vvp sim_test

# 7. Factorial Benchmark (Bonus 1)
iverilog -I src -o sim_test src/*.v sim/bonus1/tb_bonus1.v ; vvp sim_test

# 8. Exceptions & Trap Verification (Bonus 2)
iverilog -I src -o sim_test src/*.v sim/bonus2/tb_bonus2.v ; vvp sim_test
```

---

## 🚀 Building & Programming the FPGA (Vivado)

1. Open **Vivado 2020.1+** and create a new project targeting `xc7a35tcsg324-1`.
2. Add all sources:
   - `design.v` (top-level SoC integration + CPU core)
   - `src/led_matrix_controller.v`
   - `src/i2c_peripheral.v`
   - `program.hex.txt` (referenced by the Instruction ROM inside `design.v`)
   - `arty_a7.xdc` (physical constraints)
3. Add an IP core: **Clocking Wizard (`clk_wiz_0`)** → Input: 100 MHz, Output: 25 MHz.
4. Run **Synthesis → Implementation → Generate Bitstream**.
5. Program the Arty A7 via **Open Hardware Manager → Program Device**.
6. After programming: place the board flat and press **RESET (BTN0)**. Keep flat for 1.2 seconds during calibration. The water droplet will appear at center and respond to tilt.

---

## 📁 Repository Structure

```
.
├── design.v                            # Synthesizable Top-Level SoC (CPU + MMIO + Peripherals)
├── arty_a7.xdc                         # Xilinx Artix-7 Pin Constraint Map
├── program.hex.txt                     # CPU Firmware Machine Code for Instruction ROM
├── src/                                # Modular Synthesizable Verilog Subsystems
│   ├── cpu_core.v                      # 5-Stage Pipelined CPU Core Top
│   ├── defines.v                       # CPU ISA Opcode & Control Definitions
│   ├── alu.v                           # Arithmetic Logic Unit (28 Ops, MUL, MAC, Shifts)
│   ├── pc.v                            # Program Counter Register
│   ├── reg_file.v                      # 8 x 8-bit Dual-Read Single-Write Register File
│   ├── instr_memory.v                  # 256-Byte Instruction Memory
│   ├── data_memory.v                   # 256-Byte Data RAM & Memory-Mapped Peripheral Decoder
│   ├── control_unit.v                  # Main Instruction Decode & Pipeline Control Unit
│   ├── branch_pred.v                   # 32-Entry Dynamic Branch Target Buffer & Predictor
│   ├── branch_resolution_unit.v        # Branch Outcome & Mispredict Recovery Resolver
│   ├── fwd_unit.v                      # EX->EX & MEM->EX Operand Forwarding Unit
│   ├── exception_unit.v                # CP0 Coprocessor (Overflow, Illegal, Trap, Interrupts)
│   ├── int_control.v                   # Hardware Interrupt Vectoring Controller
│   ├── extender.v                      # Sign/Zero Immediate Extender
│   ├── reset_synchronizer.v            # Power-on Reset Synchronizer
│   ├── pwm_generator.v                 # 8-bit Hardware PWM Motor Generator
│   ├── uart_peripheral.v               # 115200 Baud Full-Duplex UART MMIO Controller
│   ├── uart_receiver.v                 # UART Serial Rx Deserializer
│   ├── uart_transmitter.v              # UART Serial Tx Serializer
│   ├── led_matrix_controller.v         # 8×8 Matrix Fluid Physics + DSP Filter Engine
│   ├── i2c_peripheral.v                # Hardware I2C Master Engine (100 kHz)
│   └── oled_controller.v               # Optional SPI/I2C OLED Display Controller
├── sim/                                # Verification & Simulation Testbenches
│   ├── tb_cpu_i2c.v                    # CPU + I2C + MPU-6050 Co-Simulation Testbench
│   ├── tb_i2c.v                        # Standalone I2C Protocol Engine Testbench
│   ├── clk_wiz_0_stub.v                # Clocking Wizard Simulation Model
│   ├── comprehensive_test/             # Self-Checking Verification Test Suites
│   │   ├── tb_master_suite.v           # Integrated System-Level Master Test
│   │   ├── tb_isa_instructions.v       # Complete 28-Instruction ISA Test
│   │   ├── tb_hazards_forwarding.v     # Data Hazards & Forwarding Test
│   │   ├── tb_branch_prediction.v      # Dynamic Branch Prediction & Flush Test
│   │   ├── tb_exceptions_interrupts.v  # CP0 Exceptions & Interrupt Test
│   │   ├── tb_peripherals_uart.v       # GPIO, ADC, PWM & UART TX Test
│   │   └── tb_uart_full_loopback.v     # Full Serial TX->RX Loopback Test
│   ├── bonus1/                         # Recursive Factorial Algorithm Test
│   │   ├── tb_bonus1.v                 # Factorial Testbench
│   │   ├── bonus1_factorial.asm        # Assembly Source
│   │   └── bonus_factorial.hex         # Machine Code Hex
│   ├── bonus2/                         # Exception Handling Verification
│   │   ├── tb_bonus2.v                 # Exception Testbench
│   │   ├── bonus2_programs.asm         # Exception Assembly Programs
│   │   └── *.hex                       # Overflow, Illegal, Trap Hex Files
│   ├── bonus2_individual/              # Isolated Unit Exception Testbenches
│   ├── uart/                           # Dedicated UART TX Verification Suite
│   └── end_eval/                       # Core Evaluation Benchmark Suite
└── docs/                               # Architectural Documentation & Schematics
    ├── ISA_specification.md            # Detailed Machine Instruction Encoding Manual
    └── arch.svg                        # 5-Stage CPU Architecture Diagram (SVG)
```

