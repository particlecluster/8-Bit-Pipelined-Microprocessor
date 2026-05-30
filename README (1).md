# 8-Bit Pipelined Microprocessor in Verilog

> **IIT Indore — Science & Technology Council / Students' Gymkhana**  
> Hardware Design Challenge

A fully functional 8-bit pipelined microprocessor implemented in Verilog HDL, featuring a custom ISA, a five-stage pipeline with complete hazard handling, and four architectural enhancements that form a complete hardware-software ecosystem.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
  - [Pipeline Stages](#pipeline-stages)
  - [Datapath Components](#datapath-components)
- [Instruction Set Architecture (ISA)](#instruction-set-architecture-isa)
- [Enhancements](#enhancements)
  - [1. Memory-Mapped I/O with PWM Output](#1-memory-mapped-io-with-pwm-output)
  - [2. Hardware Multiplier and MAC Instruction](#2-hardware-multiplier-and-mac-instruction)
  - [3. 1-Bit Branch History Table](#3-1-bit-branch-history-table)
  - [4. Web-Based Custom Assembler](#4-web-based-custom-assembler)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Running Simulation](#running-simulation)
- [Web Assembler](#web-assembler)
- [Project Timeline](#project-timeline)
- [Submission Checklist](#submission-checklist)
- [References](#references)

---

## Overview

This project implements a pipelined 8-bit microprocessor from scratch in Verilog. The processor is built around a custom ISA and a five-stage pipeline (IF → ID → EX → MEM → WB) with hazard-handling mechanisms including data forwarding, stall insertion, and branch control logic.

---

## Features

| # | Enhancement | Description |
|---|---|---|
| 1 | **Memory-Mapped I/O with PWM** | Address `0xFF` is a write-only PWM duty-cycle register for DRV8833 motor control |
| 2 | **Hardware Multiplier & MAC** | Combinational 8×8-bit multiplier in EX stage; `MUL` and `MAC` instructions added to the ISA |
| 3 | **1-Bit Branch History Table** | 64-entry BHT in IF stage; eliminates the 2-cycle flush penalty on correctly predicted branches |
| 4 | **Web-Based Assembler** | Browser-based tool (hosted on GitHub Pages) that assembles custom mnemonics to `$readmemh`-compatible hex files |

---

## Architecture

### Pipeline Stages

| Stage | Abbr. | Key Operations |
|---|---|---|
| Instruction Fetch | IF | PC update; instruction memory read; BHT lookup for speculative branch target selection |
| Instruction Decode | ID | Register file dual-read; immediate extension; control signal generation; hazard detection |
| Execute | EX | ALU operations; hardware multiplier (MUL/MAC); branch evaluation; forwarding muxes; MMIO address decode |
| Memory Access | MEM | Data memory read (LOAD) / write (STORE); STORE to `0xFF` updates PWM register instead of SRAM |
| Write Back | WB | Register file write from ALU result, memory read data, or MAC accumulated result |

### Datapath Components

| Component | Description |
|---|---|
| Program Counter | 8-bit register; increments each cycle; overridden by branch/jump target |
| Instruction Memory | 256 × 16-bit synchronous ROM; initialised via `$readmemh` |
| Register File | 8 × 8-bit dual-read, single-write; R0 hardwired to zero |
| ALU | Supports ADD, ADDS, SUB, SUBS, SHL, SHR, SAR, AND, OR, XOR; produces Zero, Carry, Overflow flags |
| Hardware Multiplier | Combinational 8×8→16-bit multiplier; lower 8 bits for MUL, full product for MAC |
| MAC Accumulate Path | Reads Rd as a third operand and adds product in one cycle |
| Data Memory | 256 × 8-bit synchronous SRAM (Harvard architecture) |
| MMIO / PWM Register | Address `0xFF`: write-only duty-cycle latch; reads return `0x00` |
| PWM Generator | Free-running 8-bit counter vs. duty-cycle latch; ~195 kHz at 50 MHz system clock |
| Branch History Table | 64-entry, 1-bit table in IF stage; indexed by `PC[5:0]`; accompanied by Branch Target Buffer |
| Forwarding Unit | EX-to-EX and MEM-to-EX forwarding; extended to cover MAC Rd accumulate read |
| Hazard Detection Unit | Detects load-use stalls and MAC read-after-write on Rd; generates stall and flush signals |

---

## Instruction Set Architecture (ISA)

Instructions are 16 bits wide. The processor supports 18 base instructions plus the two new instructions introduced by the hardware multiplier enhancement:

| Instruction | Format | Description |
|---|---|---|
| `MUL Rd, Rs1, Rs2` | R-Type (`EXT 0000`) | `Rd = (Rs1 × Rs2)[7:0]` — lower 8 bits of 16-bit product; 1 cycle |
| `MAC Rd, Rs1, Rs2` | R-Type (`EXT 0001`) | `Rd = Rd + (Rs1 × Rs2)[7:0]` — multiply-accumulate in a single pipeline cycle |

All immediates are either sign-extended (arithmetic) or zero-extended (logical / load-store offset) to 8 bits.

---

## Enhancements

### 1. Memory-Mapped I/O with PWM Output

Address `0xFF` is hardwired as a write-only PWM duty-cycle register. Any `STORE` instruction targeting `0xFF` bypasses SRAM and writes directly to the duty-cycle latch.

**Memory Map:**

| Address | Region | Access |
|---|---|---|
| `0x00` – `0xFE` | SRAM | Read / Write |
| `0xFF` | MMIO OUT (PWM) | Write only |

**PWM Generator:**
- Free-running 8-bit counter clocked at the system clock
- Output is high while `counter < duty_latch`
- At 50 MHz: **f_PWM ≈ 195 kHz** — within the DRV8833 switching bandwidth
- PWM connects to IN1 of the H-bridge channel; IN2 held low for forward drive

### 2. Hardware Multiplier and MAC Instruction

A combinational 8×8-bit multiplier is integrated into the Execute stage. Two new R-Type instructions are added:

- `MUL Rd, Rs1, Rs2` — stores lower 8 bits of the product in Rd
- `MAC Rd, Rs1, Rs2` — computes `Rd = Rd + (Rs1 × Rs2)[7:0]` in a single cycle

This replaces software shift-add multiply loops, significantly reducing latency for iterative control-system computations.

### 3. 1-Bit Branch History Table

Replaces the fixed "branch-not-taken" strategy, which incurs a 2-cycle flush penalty on every taken branch.

**BHT Specification:**

| Parameter | Value |
|---|---|
| Table size | 64 entries |
| Index | `PC[5:0]` |
| Entry width | 1 bit (0 = Not-Taken, 1 = Taken) |
| Branch Target Buffer | 8-bit BTB per entry (stores last resolved target PC) |
| Update policy | Bit flipped on misprediction; unchanged on correct prediction |
| Location | IF stage |

For a tight loop iterating N times, this achieves up to a **98% reduction in branch overhead**.

### 4. Web-Based Custom Assembler

A standalone web application that translates custom assembly mnemonics into `$readmemh`-compatible 16-bit hex files.

- Built with HTML, CSS, and JavaScript — no installation required
- Runs entirely in the browser
- Hosted on **GitHub Pages** (see URL in repo)
- Supports label resolution, immediate validation, and one-click hex file download
- Uses a two-pass strategy: collects labels on the first pass, resolves branch offsets and jump addresses on the second

---

## Repository Structure

```
.
├── src/
│   ├── processor.v          # Top-level processor module
│   ├── if_stage.v           # Instruction Fetch (includes BHT)
│   ├── id_stage.v           # Instruction Decode
│   ├── ex_stage.v           # Execute (ALU + Hardware Multiplier)
│   ├── mem_stage.v          # Memory Access (SRAM + MMIO)
│   ├── wb_stage.v           # Write Back
│   ├── alu.v                # ALU
│   ├── multiplier.v         # 8x8 combinational multiplier
│   ├── bht.v                # Branch History Table
│   ├── pwm_gen.v            # PWM Generator
│   ├── forwarding_unit.v    # Data forwarding logic
│   ├── hazard_unit.v        # Hazard detection
│   ├── reg_file.v           # Register file
│   ├── instr_mem.v          # Instruction memory
│   ├── data_mem.v           # Data memory (SRAM + MMIO decode)
│   ├── control_unit.v       # Control signal generation
│   ├── sign_extend.v        # Sign/zero extension unit
│   ├── pipeline_regs.v      # IF/ID, ID/EX, EX/MEM, MEM/WB registers
│   └── top.v                # Top-level with clocking
├── tb/
│   └── tb_processor.v       # Testbench with evaluation program
├── assembler/               # Web-based assembler source
├── prog/
│   └── eval_program.asm     # Evaluation program assembly source
├── docs/
│   └── 8bit_processor_proposal.doc
├── vivado/                  # Vivado project files
└── README.md
```

---

## Getting Started

### Prerequisites

- [Xilinx Vivado](https://www.xilinx.com/products/design-tools/vivado.html) (Design Suite)
- A text editor or IDE with Verilog support

### Build Instructions

1. **Clone the repository:**
   ```bash
   git clone https://github.com/<your-org>/<repo-name>.git
   cd <repo-name>
   ```

2. **Open the Vivado project:**
   - Launch Vivado and open `vivado/<project>.xpr`, or
   - Create a new project and add all `.v` files from `src/` as sources

3. **Load the evaluation program:**
   - Use the Web Assembler (see below) to generate a hex file from `prog/eval_program.asm`
   - Place the output hex file where `$readmemh` expects it (see `instr_mem.v`)

4. **Synthesise and implement** using Vivado's standard flow.

---

## Running Simulation

Run the provided testbench in Vivado's simulator:

```
Testbench: tb/tb_processor.v
```

The testbench loads the evaluation program, monitors the PWM output signal, and logs pipeline activity. Key signals to observe:

- `pwm_out` — toggles at ~195 kHz; duty cycle changes as the PID loop executes
- `MAC` instruction cycle count vs. software multiply-loop baseline
- BHT prediction accuracy over the evaluation loop

---

## Web Assembler

The assembler is hosted on GitHub Pages:

**URL:** `https://<your-org>.github.io/<repo-name>/assembler/`

**Usage:**
1. Write or paste assembly code in the editor pane
2. Click **Assemble**
3. Review any label or immediate validation errors
4. Click **Download Hex** to get the `$readmemh`-compatible `.hex` file

The assembler supports all 18 base ISA instructions plus `MUL` and `MAC`, full label resolution, and MMIO address annotations.

---

## Project Timeline

| Phase | Week(s) | Milestone |
|---|---|---|
| Setup & ISA Finalisation | 1 | Repository created; ISA and features locked; Vivado skeleton committed |
| Single-Cycle Core | 2–3 | All 18 instructions functional in simulation; MUL/MAC unit tests pass |
| Data Hazards & MUL/MAC | 5 | Forwarding unit and load-use stall logic verified; RAW hazard suite passes; MUL/MAC benchmarked |
| MMIO & PWM | 7 | MMIO address decode; PWM generator; `STORE`-to-`0xFF` waveform verified |
| Assembler & Integration | 6–8 | Assembler deployed on GitHub Pages; evaluation program assembled and loaded into testbench |
| Final Integration & Report | Final | All features integrated; benchmarks complete; report and waveform captures submitted |

---

## Submission Checklist

- [ ] Public GitHub repository with complete Vivado project
- [ ] All 19 synthesisable Verilog source files on `main`
- [ ] Testbench (`tb_processor.v`) with evaluation program; PWM output monitored
- [ ] This README with build instructions, module hierarchy, and assembler URL
- [ ] Project proposal document in repository root
- [ ] Final report: architecture rationale, hazard analysis, BHT benchmark, Vivado waveforms
- [ ] HDLBits 7458 screenshots from all four team members (Appendix A)
- [ ] MMIO / PWM waveform capture demonstrating a DRV8833-compatible signal
- [ ] MUL/MAC benchmark: cycle count vs. software multiply-loop baseline
- [ ] Branch prediction accuracy report for the evaluation program
- [ ] Web Assembler live on GitHub Pages with URL in this README
- [ ] *(Bonus)* C PID program, manually compiled assembly listing, and C-to-ISA mapping document

---

## References

1. *Hardware Modelling using Verilog* — ISA design, pipelining, and hazard taxonomy
2. *Computer Organization and Design* (Patterson & Hennessy) — Chapter 4 (pipelining), Section 4.8 (branch prediction, BHT)
3. [HDLBits](https://hdlbits.01xz.net/) — Verilog practice platform; mandatory 7458 problem
4. [DRV8833 Dual H-Bridge Motor Driver Datasheet](https://www.ti.com/product/DRV8833) — Texas Instruments
5. Stack Overflow: *Implementation of a Simple Microprocessor using Verilog*
