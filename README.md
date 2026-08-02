# 8-Bit Custom Embedded CPU

A single-cycle, 8-bit soft-core processor written in Verilog. It executes 16-bit instructions and features a custom ALU, a unified Register File, and memory-mapped I/O tailored for embedded hardware control.

## Key Features
* **Architecture:** 8-bit data path, 8-bit memory addressing, 16-bit instruction width.
* **Execution:** Single-cycle, non-pipelined architecture.
* **Registers:** 8 general-purpose 8-bit registers (`R0` is hardwired to `0x00`).
* **Memory-Mapped I/O:** Built-in PWM generator mapped to memory address `0xFF` for direct hardware control (e.g., DC motors).

## Hardware Modules
* `CPU_Core`: The top-level module routing datapath wires and control signals.
* `ProgramCounter`: Manages the 8-bit instruction pointer, handling sequential increments, branches, and halts.
* `InstructionMemory`: 256-word ROM initialized via `program.hex`.
* `ControlUnit`: Hardwired decoder translating 5-bit opcodes into datapath routing signals.
* `RegisterFile`: 8x8-bit memory block with 2 read ports, 1 dedicated ALU read port, and 1 write port.
* `ALU`: Supports arithmetic (ADD, SUB, MAC), logic (AND, OR, XOR), shifts, and 8x8-bit multiplication.
* `DataMemory`: 255 bytes of RAM, bypassing address `0xFF` to the PWM peripheral.
* `PWM_Generator`: Hardware timer that converts an 8-bit duty cycle into a continuous PWM waveform on `motor_pwm_pin`.
* `ResetSynchronizer`: A 2-stage flip-flop circuit that safely converts an asynchronous external reset into a stable, synchronous system reset.
* `Extender`: Expands 5-bit immediate values into 8-bit sign-extended and zero-extended formats for the ALU and memory addressing.

## Memory Map
* `0x00 - 0xFE`: Standard Data RAM.
* `0xFF`: PWM Duty Cycle Register. Writing to this address immediately updates the `motor_pwm_pin` output waveform.

## Simulation & Usage
1. Compile your assembly code into 16-bit hex instructions.
2. Place the resulting hex file in the root directory and name it `program.hex`.
3. Provide a clock signal (`clk`) and an active-high reset (`rst`) to the `CPU_Core`.
4. Observe the `motor_pwm_pin` output for hardware control.
![CPU Architecture](docs/arch.svg)
