# 5-Stage Pipelined CPU Core

**Team elec_03 | IIT Indore**

A custom 16-bit instruction, 8-bit data pipelined microprocessor written in Verilog. This core implements a classic 5-stage pipeline (Fetch, Decode, Execute, Memory, Write-Back) with advanced architectural features including hardware branch prediction, full data forwarding, and memory-mapped peripherals.

## Microarchitecture Diagram

Click the diagram below to open the interactive, zoomable vector graphic.

[](https://www.google.com/search?q=cpu_architecture.svg)
*(Make sure to upload your `cpu_architecture.svg` to the repo for this link to work!)*

## Key Features

* **5-Stage Pipeline:** Instruction Fetch (IF), Instruction Decode (ID), Execute (EX), Memory (MEM), and Write-Back (WB).
* **Data Hazard Resolution:** Integrated Forwarding Unit (EX->EX and MEM->EX) and a Hazard Detection Unit to stall on load-use hazards.
* **Branch Prediction:** Hardware Branch Target Buffer (BTB) and Branch History Table (BHT) to minimize control hazards.
* **Exception & Interrupt Handling:** Integrated Coprocessor 0 (CP0) handles ALU overflows, illegal instructions, traps, and external hardware interrupts via `epc` and `cause` registers.
* **Custom ISA:** 16-bit instructions, 5-bit opcodes, and 8 general-purpose registers (3-bit addressing). Supports Arithmetic, Logical, Memory, and Branching operations (including MAC).

## Memory-Mapped I/O

The CPU interacts with the outside world using memory-mapped peripherals mapped to the top of the 8-bit address space:

* `0xFF` - **PWM Motor Control:** Write duty cycle here to control `motor_pwm_pin`.
* `0xFE` - **Digital Inputs:** Read external digital pins.
* `0xFD` - **ADC Inputs:** Read external analog-to-digital converter pins.
* `0xFC` - **UART TX:** Write data here to transmit via UART.
* `0xFB` - **UART RX:** Read received UART data.
* `0xFA` - **UART Status:** Check RX overrun, TX ready, and RX valid flags.

## Module Overview

* `CPU_Core_5Stage`: The top-level module wiring the pipeline registers.
* `ControlUnit`: Centralized opcode decoder.
* `ALU`: Performs arithmetic and logical operations, including hardware multiplication and overflow detection.
* `BranchPredictor` & `BranchResolutionUnit`: Handles speculative execution and pipeline flushes on mispredicts.
* `Exception_Unit`: Hardware trap and exception routing.
* `UART_Peripheral`: 8-N-1 asynchronous serial communication block (115200 baud at 50MHz).
<a href="docs/arch.svg" target="_blank">
  <img src="docs/arch.svg" alt="CPU Architecture" width="100%">
</a>
