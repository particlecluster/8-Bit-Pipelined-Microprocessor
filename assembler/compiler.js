// compiler.js

class CustomAssembler {
    constructor() {
        // Mapped directly from your `define OP_ statements
        this.opcodes = {
            ADD: 0x00, SUB: 0x01, AND: 0x02, OR: 0x03, 
            XOR: 0x04, SHL: 0x05, SHR: 0x06, LDI: 0x07,
            LDD: 0x08, STR: 0x09, JMP: 0x0A, JZ: 0x0B, 
            JNZ: 0x0C, JGT: 0x0D, ADDI: 0x0E, SLT: 0x0F,
            MUL: 0x10, MAC: 0x11, ROL: 0x12, ROR: 0x13, 
            RETI: 0x14, STD: 0x15, JAL: 0x16, JR: 0x17, 
            HALT: 0x1F
        };
    }

    // Helper: Extract integer from "R1", "R7", etc.
    parseReg(regStr) {
        return parseInt(regStr.replace('R', ''), 10) & 0x07;
    }

    // Helper: Handle negative two's complement and standard hex/decimal
    parseImm(immStr, bits) {
        let val = parseInt(immStr, 0); // Parses standard '10' or hex '0xFF'
        if (val < 0) {
            val = (1 << bits) + val; // Two's complement for negative offsets
        }
        return val & ((1 << bits) - 1); // Mask to max bit width
    }

    assemble(sourceCode) {
        const lines = sourceCode.split('\n');
        const hexOutput = [];

        lines.forEach((line, index) => {
            // Strip comments and trim
            let cleanLine = line.split('//')[0].trim();
            if (!cleanLine) return; 

            // Split by spaces or commas
            const tokens = cleanLine.split(/[ ,]+/).filter(t => t !== '');
            const mnemonic = tokens[0].toUpperCase();
            const op = this.opcodes[mnemonic];

            if (op === undefined) {
                throw new Error(`Syntax Error on line ${index + 1}: Unknown instruction '${mnemonic}'`);
            }

            let bin = op << 11; // Shift 5-bit opcode to [15:11]

            // Format R: ALU Operations (e.g., ADD RD, RS1, RS2)
            if (['ADD','SUB','AND','OR','XOR','SHL','SHR','SLT','MUL','MAC','ROL','ROR'].includes(mnemonic)) {
                let rd  = this.parseReg(tokens[1]);
                let rs1 = this.parseReg(tokens[2]);
                let rs2 = this.parseReg(tokens[3]);
                bin |= (rd << 8) | (rs1 << 5) | (rs2 << 2);
            } 
            // Format I8: 8-bit Immediates (e.g., LDI RD, IMM8 or STD RS, IMM8)
            else if (['LDI','STD','JZ','JNZ','JGT','JAL'].includes(mnemonic)) {
                let reg  = this.parseReg(tokens[1]);
                let imm8 = this.parseImm(tokens[2], 8);
                bin |= (reg << 8) | imm8;
            } 
            // Format I5: 5-bit Immediates (e.g., ADDI RD, RS1, IMM5 or STR R_DATA, R_BASE, IMM5)
            else if (['ADDI','LDD','STR'].includes(mnemonic)) {
                let reg1 = this.parseReg(tokens[1]);
                let reg2 = this.parseReg(tokens[2]);
                let imm5 = this.parseImm(tokens[3], 5);
                bin |= (reg1 << 8) | (reg2 << 5) | imm5;
            } 
            // Format JMP: Unconditional Jump (JMP IMM8)
            else if (mnemonic === 'JMP') {
                let imm8 = this.parseImm(tokens[1], 8);
                bin |= imm8;
            } 
            // Format JR: Jump Register (JR RS1)
            else if (mnemonic === 'JR') {
                let rs1 = this.parseReg(tokens[1]);
                bin |= (rs1 << 8);
            } 
            // Format N: No Operands (HALT, RETI)
            else if (['HALT','RETI'].includes(mnemonic)) {
                // bin is already just the opcode << 11
            }

            // Convert integer to 4-character padded hexadecimal string
            let hexStr = bin.toString(16).toUpperCase().padStart(4, '0');
            hexOutput.push(hexStr);
        });

        return hexOutput;
    }
}

// === QUICK TEST ===
// Let's test storing a duty cycle to your PWM pin (address 0xFF)
const assembler = new CustomAssembler();
const testCode = `
    LDI R1, 128    // Load 128 into R1
    STD R1, 0xFF   // Store R1 to mem address 255 (PWM)
    HALT
`;
console.log(assembler.assemble(testCode)); 
// Should output: [ '3980', 'A9FF', 'F800' ]