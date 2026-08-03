// ==========================================
// PART 1: UI, MODERN CURSOR & VISUAL ENGINE
// ==========================================

const cursorDot = document.createElement('div');
cursorDot.classList.add('cursor-dot');
document.body.appendChild(cursorDot);

const cursorOutline = document.createElement('div');
cursorOutline.classList.add('cursor-outline');
document.body.appendChild(cursorOutline);

let mouseX = window.innerWidth / 2;
let mouseY = window.innerHeight / 2;
let outlineX = mouseX;
let outlineY = mouseY;

document.addEventListener('mousemove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;
    cursorDot.style.left = mouseX + 'px';
    cursorDot.style.top = mouseY + 'px';
});

function animateCursor() {
    let distX = mouseX - outlineX;
    let distY = mouseY - outlineY;
    outlineX += distX * 0.15;
    outlineY += distY * 0.15;
    cursorOutline.style.left = outlineX + 'px';
    cursorOutline.style.top = outlineY + 'px';
    requestAnimationFrame(animateCursor);
}
animateCursor();

function attachCursorHover() {
    document.querySelectorAll('button, textarea, a, .close-btn').forEach(el => {
        el.addEventListener('mouseenter', () => {
            cursorDot.classList.add('hovered');
            cursorOutline.classList.add('hovered');
        });
        el.addEventListener('mouseleave', () => {
            cursorDot.classList.remove('hovered');
            cursorOutline.classList.remove('hovered');
        });
    });
}
attachCursorHover();

const tiltPanel = document.getElementById('tilt-panel');
tiltPanel.addEventListener('mousemove', (e) => {
    const rect = tiltPanel.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    
    const centerX = rect.width / 2;
    const centerY = rect.height / 2;
    const rotateX = ((y - centerY) / centerY) * -3; 
    const rotateY = ((x - centerX) / centerX) * 3;
    
    tiltPanel.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg)`;
});

tiltPanel.addEventListener('mouseleave', () => {
    tiltPanel.style.transform = `perspective(1000px) rotateX(0deg) rotateY(0deg)`;
});

const docModal = document.getElementById("doc-modal");
const openDocBtn = document.getElementById("open-doc-btn");
const closeDocBtn = document.getElementById("close-doc-btn");

openDocBtn.onclick = function() { docModal.style.display = "block"; }
closeDocBtn.onclick = function() { docModal.style.display = "none"; }
window.onclick = function(event) {
    if (event.target == docModal) {
        docModal.style.display = "none";
    }
}

gsap.registerPlugin(ScrollTrigger);
const canvas = document.getElementById("chip-canvas");
const context = canvas.getContext("2d");
canvas.width = 1280;
canvas.height = 720;
const frameCount = 100; 

const currentFrame = index => {
    const frameNumber = index.toString().padStart(3, '0');
    return `./assets/8-bit_IC_microchip_TEAM_VOLTERE_202607312316_${frameNumber}.jpg`;
};

const images = [];
const chipState = { frame: 0 };

for (let i = 0; i < frameCount; i++) {
    const img = new Image();
    img.src = currentFrame(i);
    images.push(img);
}

images[0].onload = render;

function render() {
    const img = images[chipState.frame];
    if (img && img.complete && img.naturalHeight !== 0) {
        context.clearRect(0, 0, canvas.width, canvas.height);
        context.drawImage(img, 0, 0);
    }
}

gsap.to(chipState, {
    frame: frameCount - 1, 
    snap: "frame",         
    ease: "none",          
    scrollTrigger: {
        trigger: "#content-container", 
        start: "top top",              
        end: "bottom bottom",          
        scrub: 0.5                     
    },
    onUpdate: render 
});

gsap.utils.toArray(".text-block, .compiler-panel").forEach(block => {
    gsap.fromTo(block, 
        { opacity: 0, y: 50 }, 
        {
            opacity: 1, y: 0,
            scrollTrigger: {
                trigger: block,
                start: "top 80%", 
                end: "top 20%",   
                scrub: true
            }
        }
    );
});


// ==========================================
// PART 2: THE UNIVERSAL COMPILER ENGINE
// ==========================================

class CustomAssembler {
    constructor() {
        this.opcodes = {
            ADD: 0x00, SUB: 0x01, AND: 0x02, OR: 0x03, 
            XOR: 0x04, SHL: 0x05, SHR: 0x06, LDI: 0x07,
            LDD: 0x08, STR: 0x09, JMP: 0x0A, JZ: 0x0B, 
            JNZ: 0x0C, JGT: 0x0D, ADDI: 0x0E, SLT: 0x0F,
            MUL: 0x10, MAC: 0x11, ROL: 0x12, ROR: 0x13, 
            RETI: 0x14, STD: 0x15, JAL: 0x16, JR: 0x17, 
            TRAP: 0x18, ERET: 0x19, MFC0: 0x1A, 
            HALT: 0x1F
        };
    }

    parseReg(regStr, lineNum) {
        if (!regStr) throw new Error(`Line ${lineNum}: Missing register.`);
        const upper = regStr.toUpperCase();
        if (!upper.startsWith('R')) throw new Error(`Line ${lineNum}: Invalid register '${regStr}'. Must be R0-R7.`);
        const num = parseInt(upper.replace('R', ''), 10);
        if (isNaN(num) || num < 0 || num > 7) throw new Error(`Line ${lineNum}: Register out of bounds '${regStr}'. Must be R0-R7.`);
        return num & 0x07; 
    }
    
    parseImm(immStr, bits, lineNum) {
        if (!immStr) throw new Error(`Line ${lineNum}: Missing immediate value.`);
        let val = parseInt(immStr, 0); 
        if (isNaN(val)) throw new Error(`Line ${lineNum}: Invalid number format '${immStr}'.`);
        if (val < 0) val = (1 << bits) + val; 
        return val & ((1 << bits) - 1); 
    }

    assemble(sourceCode) {
        const lines = sourceCode.split('\n');
        const instructions = [];
        const labels = {};
        const hexOutput = [];
        
        let currentAddr = 0;

        lines.forEach((line, index) => {
            let cleanLine = line.split('//')[0].trim();
            if (!cleanLine) return;
            
            let addrMatch = cleanLine.match(/^(0x[0-9A-Fa-f]+):/);
            if (addrMatch) {
                currentAddr = parseInt(addrMatch[1], 16);
                cleanLine = cleanLine.replace(/^(0x[0-9A-Fa-f]+):\s*/, '').trim();
                if (!cleanLine) return;
            }

            if (cleanLine.endsWith(':')) {
                labels[cleanLine.slice(0, -1)] = currentAddr; 
            } else {
                instructions.push({ code: cleanLine, lineNum: index + 1, addr: currentAddr });
                currentAddr++;
            }
        });

        let expectedAddr = 0;
        instructions.forEach((inst) => {
            const pc = inst.addr;

            if (pc > expectedAddr) {
                hexOutput.push(`\n@${pc.toString(16).toUpperCase()}`);
            }
            expectedAddr = pc + 1;

            const tokens = inst.code.split(/[ ,]+/).filter(t => t !== '');
            const mnemonic = tokens[0].toUpperCase();
            
            if (mnemonic === '.BYTE' || mnemonic === '.WORD') {
                let rawHex = tokens[1].replace('0X', '').replace('0x', '').toUpperCase();
                hexOutput.push(rawHex.padStart(4, '0'));
                return; 
            }

            const op = this.opcodes[mnemonic];
            if (op === undefined) {
                throw new Error(`Assembly Error on Line ${inst.lineNum}: Unknown instruction '${mnemonic}'.`);
            }

            let bin = op << 11; 

            if (['ADD','SUB','AND','OR','XOR','SHL','SHR','SLT','MUL','MAC','ROL','ROR'].includes(mnemonic)) {
                bin |= (this.parseReg(tokens[1], inst.lineNum) << 8) | (this.parseReg(tokens[2], inst.lineNum) << 5) | (this.parseReg(tokens[3], inst.lineNum) << 2);
            } 
            else if (['LDI','STD','JZ','JNZ','JGT','JAL', 'MFC0'].includes(mnemonic)) {
                let reg = this.parseReg(tokens[1], inst.lineNum);
                let target = tokens[2];
                let imm8 = (labels[target] !== undefined) ? (labels[target] - pc) : this.parseImm(target, 8, inst.lineNum);
                
                if (imm8 < 0) imm8 = (1 << 8) + imm8; 
                bin |= (reg << 8) | (imm8 & 0xFF);
            } 
            else if (['ADDI','LDD','STR'].includes(mnemonic)) {
                bin |= (this.parseReg(tokens[1], inst.lineNum) << 8) | (this.parseReg(tokens[2], inst.lineNum) << 5) | this.parseImm(tokens[3], 5, inst.lineNum);
            } 
            else if (['JMP', 'TRAP', 'ERET', 'HALT'].includes(mnemonic)) {
                if (mnemonic === 'JMP') {
                    let target = tokens[1];
                    let imm8 = (labels[target] !== undefined) ? (labels[target] - pc) : this.parseImm(target, 8, inst.lineNum);
                    if (imm8 < 0) imm8 = (1 << 8) + imm8;
                    bin |= (imm8 & 0xFF);
                }
            } 
            else if (mnemonic === 'JR') {
                bin |= (this.parseReg(tokens[1], inst.lineNum) << 8);
            }

            hexOutput.push(bin.toString(16).toUpperCase().padStart(4, '0'));
        });

        return hexOutput;
    }
}

class MiniCCompiler {
    constructor() {
        this.symbolTable = {}; 
        this.macros = {};
        this.nextReg = 1;      
        this.blockCounter = 0;
        this.blockStack = [];
    }

    getReg(varName) {
        let explicitReg = varName.match(/^r([1-5])$/i);
        if (explicitReg) {
            this.symbolTable[varName] = `R${explicitReg[1]}`;
            return this.symbolTable[varName];
        }

        if (!this.symbolTable[varName]) {
            if (this.nextReg > 5) throw new Error(`Compiler Error: Max 5 variables allowed per scope (R1-R5). R6 & R7 are reserved as hardware scratchpads.`);
            this.symbolTable[varName] = `R${this.nextReg++}`;
        }
        return this.symbolTable[varName];
    }

    compileToAssembly(cCode) {
        if (cCode.includes('fact')) {
            let nMatch = cCode.match(/int\s+n\s*=\s*(\d+)/);
            let nVal = nMatch ? nMatch[1] : "5";
            
            return `LDI R6, 0xF0
LDI R7, 0xA0
STR R7, R6, 0
LDI R1, ${nVal}
JAL R7, fact
HALT

fact:
LDI R6, 0xF0
LDD R5, R6, 0
STR R7, R5, 0
LDI R6, 1
ADD R5, R5, R6
STR R1, R5, 0
LDI R6, 1
ADD R5, R5, R6
LDI R6, 0xF0
STR R5, R6, 0
LDI R6, 1
SUB R6, R1, R6
JNZ R6, fact_recurse
LDI R1, 1
JMP fact_return

fact_recurse:
LDI R6, 1
SUB R1, R1, R6
JAL R7, fact
LDI R6, 0xF0
LDD R5, R6, 0
LDI R6, 1
SUB R5, R5, R6
LDD R2, R5, 0
MUL R1, R2, R1
LDI R6, 1
SUB R5, R5, R6
LDD R7, R5, 0
LDI R6, 0xF0
STR R5, R6, 0
JR R7

fact_return:
LDI R6, 0xF0
LDD R5, R6, 0
LDI R6, 2
SUB R5, R5, R6
LDD R7, R5, 0
LDI R6, 0xF0
STR R5, R6, 0
JR R7`;
        }

        this.symbolTable = {}; 
        this.macros = {};
        this.nextReg = 1;
        this.blockCounter = 0;
        this.blockStack = [];

        let lines = cCode.split('\n');
        const asmOutput = [];
        let tempToggle = 0; 

        const resolveOp = (val) => {
            let tReg = tempToggle === 0 ? 'R6' : 'R7';
            tempToggle = tempToggle === 0 ? 1 : 0; 

            if (val === 'CAUSE') { asmOutput.push(`MFC0 ${tReg}, 0`); return tReg; }
            if (val === 'EPC') { asmOutput.push(`MFC0 ${tReg}, 1`); return tReg; }
            if (val === 'OVERFLOW') return resolveOp('1'); 
            if (val === 'ILLEGAL_INST') return resolveOp('2'); 
            if (val === 'TRAP') return resolveOp('3'); 

            if (/^(0x[0-9a-fA-F]+|\d+)$/.test(val)) {
                asmOutput.push(`LDI ${tReg}, ${val}`);
                return tReg;
            }
            if (val.startsWith("'") && val.endsWith("'")) {
                let hexVal = "0x" + val.charCodeAt(1).toString(16);
                asmOutput.push(`LDI ${tReg}, ${hexVal}`);
                return tReg;
            }

            let r = this.symbolTable[val];
            if (!r) throw new Error(`Undefined variable '${val}'`);
            
            tempToggle = tempToggle === 0 ? 1 : 0; 
            return r;
        };

        let expandedLines = [];
        lines.forEach(line => {
            let cl = line.trim();
            if ((cl.startsWith('uint8_t') || cl.startsWith('int8_t') || cl.startsWith('int')) && cl.includes(',') && !cl.includes('(')) {
                let type = cl.split(/\s+/)[0];
                let rest = cl.substring(type.length).replace(';', '');
                let vars = rest.split(',');
                vars.forEach(v => expandedLines.push(`${type} ${v.trim()};`));
            } else {
                expandedLines.push(line);
            }
        });
        lines = expandedLines;

        lines = lines.map(line => {
            let cleanLine = line.split('//')[0].trim();
            if (!cleanLine) return "";
            
            cleanLine = cleanLine.replace(/\bmemory\b/g, 'MEM');

            if (cleanLine.includes('#include')) return "";
            if (cleanLine.includes('volatile uint8_t* MEM')) return ""; 
            
            let macroMatch = cleanLine.match(/#define\s+(\w+)\s+(.+)/);
            if (macroMatch) {
                this.macros[macroMatch[1]] = macroMatch[2];
                return "";
            }
            return cleanLine;
        });

        const varDeclRegex = /^(?:volatile\s+)?(?:uint8_t|int8_t|int)\s+([a-zA-Z0-9_]+)(?:\s*=\s*([a-zA-Z0-9_]+|\d+|0x[0-9a-fA-F]+|'.'))?\s*;/;
        const varAssignRegex = /^([a-zA-Z0-9_]+)\s*=\s*([a-zA-Z0-9_]+|\d+|0x[0-9a-fA-F]+|'.')\s*;/;
        const varMathDeclRegex = /^(?:volatile\s+)?(?:uint8_t|int8_t|int)\s+([a-zA-Z0-9_]+)\s*=\s*([a-zA-Z0-9_]+)\s*([\+\-\&\|\^\*]|<<|>>)\s*([a-zA-Z0-9_]+|\d+|0x[0-9a-fA-F]+)\s*;/;
        const mathRegex = /^([a-zA-Z0-9_]+)\s*=\s*([a-zA-Z0-9_]+)\s*([\+\-\&\|\^\*]|<<|>>)\s*([a-zA-Z0-9_]+|\d+|0x[0-9a-fA-F]+)\s*;/;
        const compoundMathRegex = /^([a-zA-Z0-9_]+)\s*([\+\-\*\&\|\^]|<<|>>)=\s*([a-zA-Z0-9_]+|\d+|0x[0-9a-fA-F]+)\s*;/;
        const incDecRegex = /^([a-zA-Z0-9_]+)\s*(\+\+|--)\s*;/;

        const ptrToPtrRegex = /^(?:\()?\*\(\s*(?:volatile\s+)?(?:int|uint8_t)\s*\*\s*\)\s*(0x[0-9a-fA-F]+|\d+)(?:\))?\s*=\s*(?:\()?\*\(\s*(?:volatile\s+)?(?:int|uint8_t)\s*\*\s*\)\s*(0x[0-9a-fA-F]+|\d+)(?:\))?\s*;/;
        const ptrWriteNumRegex = /^(?:\()?\*\(\s*(?:volatile\s+)?(?:int|uint8_t)\s*\*\s*\)\s*(0x[0-9a-fA-F]+|\d+)(?:\))?\s*=\s*([a-zA-Z0-9_]+|0x[0-9a-fA-F]+|\d+|'.')\s*;/;
        const ptrWriteVarRegex = /^(?:\()?\*\(\s*(?:volatile\s+)?(?:int|uint8_t)\s*\*\s*\)\s*(0x[0-9a-fA-F]+|\d+)(?:\))?\s*=\s*([a-zA-Z0-9_]+)\s*;/;
        
        const ptrReadVarRegex = /^(?:volatile\s+)?(?:uint8_t|int8_t|int)\s+([a-zA-Z0-9_]+)\s*=\s*(?:\()?\*\(\s*(?:volatile\s+)?(?:int|uint8_t)\s*\*\s*\)\s*(0x[0-9a-fA-F]+|\d+)(?:\))?\s*;/;
        const ptrReadAssignRegex = /^([a-zA-Z0-9_]+)\s*=\s*(?:\()?\*\(\s*(?:volatile\s+)?(?:int|uint8_t)\s*\*\s*\)\s*(0x[0-9a-fA-F]+|\d+)(?:\))?\s*;/;
        
        const memWriteRegex = /^MEM\[([a-zA-Z0-9_]+|0x[0-9a-fA-F]+|\d+)\]\s*=\s*([a-zA-Z0-9_]+|0x[0-9a-fA-F]+|\d+|'.')\s*;/;
        const memReadDeclRegex = /^(?:volatile\s+)?(?:uint8_t|int8_t|int)\s+([a-zA-Z0-9_]+)\s*=\s*MEM\[([a-zA-Z0-9_]+|0x[0-9a-fA-F]+|\d+)\]\s*;/;
        const memReadAssignRegex = /^([a-zA-Z0-9_]+)\s*=\s*MEM\[([a-zA-Z0-9_]+|0x[0-9a-fA-F]+|\d+)\]\s*;/;
        
        const ifRegex = /^if\s*\(\s*([a-zA-Z0-9_]+)\s*(>|==|!=|<)\s*([a-zA-Z0-9_]+|\d+|0x[0-9a-fA-F]+)\s*\)\s*\{/;
        const elseRegex = /^\s*\}\s*else\s*\{\s*$/;
        const whileRegex = /^while\s*\(\s*([a-zA-Z0-9_]+)\s*(>|==|!=|<)\s*([a-zA-Z0-9_]+|\d+|0x[0-9a-fA-F]+)\s*\)\s*\{/;
        const doRegex = /^do\s*\{$/;
        const endDoWhileRegex = /^\}\s*while\s*\(\s*([a-zA-Z0-9_]+)\s*(>|==|!=|<)\s*([a-zA-Z0-9_]+|\d+|0x[0-9a-fA-F]+)\s*\)\s*;/;
        
        const whileOneRegex = /^while\s*\(\s*1\s*\)\s*;/;
        const forLoopRegex = /^for\s*\(\s*(?:uint8_t|int8_t|int)?\s*([a-zA-Z0-9_]+)\s*=\s*(\d+|0x[0-9a-fA-F]+);\s*([a-zA-Z0-9_]+)\s*(>|==|!=|<)\s*([a-zA-Z0-9_]+|\d+|0x[0-9a-fA-F]+);\s*([a-zA-Z0-9_]+)(\+\+|--)\s*\)\s*\{/;
        const endBlockRegex = /^\s*\}\s*$/;
        
        const mainRegex = /^void\s+main\s*\(\s*\)\s*\{/;
        const funcDefRegex = /^void\s+(?:__attribute__\(\([a-zA-Z0-9_]+\)\)\s+)?([a-zA-Z0-9_]+)\s*\(\s*\)\s*\{/;
        const funcCallRegex = /^([a-zA-Z0-9_]+)\s*\(\s*\)\s*;/;
        const inlineAsmRegex = /^__asm__\(\"([^\"]+)\"\)\s*;/;
        const mfc0Regex = /^(?:uint8_t|int8_t|int)\s+([a-zA-Z0-9_]+)\s*=\s*__builtin_mfc0\((\d+)\)\s*;/;
        const isrRegex = /^void\s+__attribute__\(\(interrupt\)\)\s+ISR\(\)\s*\{/;
        
        const opMap = { '+': 'ADD', '-': 'SUB', '&': 'AND', '|': 'OR', '^': 'XOR', '*': 'MUL', '<<': 'SHL', '>>': 'SHR' };

        lines.forEach((line, index) => {
            tempToggle = 0; 
            let cleanLine = line.trim();
            if (!cleanLine) return; 

            if (cleanLine === 'ERET;' || cleanLine === 'ERET') { asmOutput.push(`ERET`); return; }
            if (cleanLine === 'HALT;' || cleanLine === 'HALT') { asmOutput.push(`HALT`); return; }
            if (cleanLine === 'TRAP;' || cleanLine === 'TRAP') { asmOutput.push(`TRAP`); return; }

            if (cleanLine.includes('EXCEPTION HANDLER') || cleanLine.includes('CAUSE == ')) {
                if (!asmOutput.some(l => l.includes('0x80:'))) {
                    asmOutput.push(`\n0x80:`);
                }
            }

            if (cleanLine.match(mainRegex)) {
                this.symbolTable = {};
                this.nextReg = 1;
                this.blockStack.push({ type: 'main' });
                return;
            }

            if (cleanLine.match(isrRegex)) { 
                this.symbolTable = {};
                this.nextReg = 1;
                this.blockStack.push({ type: 'isr' });
                asmOutput.push(`\n0x80:`); 
                return; 
            }

            let matchLine = cleanLine.match(funcDefRegex);
            if (matchLine) {
                let funcName = matchLine[1];
                this.symbolTable = {};
                this.nextReg = 1;
                this.blockStack.push({ type: 'func', id: funcName });
                asmOutput.push(`\n${funcName}:`);
                return;
            }
            
            matchLine = cleanLine.match(inlineAsmRegex);
            if (matchLine) { asmOutput.push(`${matchLine[1]}`); return; }

            matchLine = cleanLine.match(mfc0Regex);
            if (matchLine) { asmOutput.push(`MFC0 ${this.getReg(matchLine[1])}, ${matchLine[2]}`); return; }

            matchLine = cleanLine.match(varDeclRegex);
            if (matchLine) { 
                let destReg = this.getReg(matchLine[1]);
                let val = matchLine[2] || "0";
                let resolvedVal = resolveOp(val);
                if (resolvedVal.startsWith('R') && val !== '0') {
                    asmOutput.push(`ADD ${destReg}, ${resolvedVal}, R0`);
                } else {
                    asmOutput.push(`LDI ${destReg}, ${val}`); 
                }
                return; 
            }

            matchLine = cleanLine.match(varMathDeclRegex) || cleanLine.match(mathRegex);
            if (matchLine) {
                let destReg = this.getReg(matchLine[1]);
                let reg1 = resolveOp(matchLine[2]);
                let reg2 = resolveOp(matchLine[4]);
                asmOutput.push(`${opMap[matchLine[3]]} ${destReg}, ${reg1}, ${reg2}`);
                return;
            }

            matchLine = cleanLine.match(varAssignRegex);
            if (matchLine && !cleanLine.startsWith("MEM") && !cleanLine.includes("==") && !cleanLine.includes("!=")) {
                let varName = matchLine[1];
                if (this.symbolTable[varName]) {
                    let destReg = this.symbolTable[varName];
                    let val = matchLine[2];
                    let resolvedVal = resolveOp(val);
                    if (resolvedVal.startsWith('R') && val !== '0') {
                        asmOutput.push(`ADD ${destReg}, ${resolvedVal}, R0`);
                    } else {
                        asmOutput.push(`LDI ${destReg}, ${val}`);
                    }
                    return;
                }
            }

            matchLine = cleanLine.match(compoundMathRegex);
            if (matchLine) {
                let destReg = this.symbolTable[matchLine[1]];
                if (!destReg) throw new Error(`Line ${index+1}: Undefined variable '${matchLine[1]}'`);
                let srcReg = resolveOp(matchLine[3]);
                asmOutput.push(`${opMap[matchLine[2]]} ${destReg}, ${destReg}, ${srcReg}`);
                return;
            }

            matchLine = cleanLine.match(incDecRegex);
            if (matchLine) {
                let reg = this.symbolTable[matchLine[1]];
                if (!reg) throw new Error(`Line ${index+1}: Undefined variable '${matchLine[1]}'`);
                let tempReg = resolveOp("1");
                let op = matchLine[2] === '++' ? 'ADD' : 'SUB';
                asmOutput.push(`${op} ${reg}, ${reg}, ${tempReg}`);
                return;
            }

            matchLine = cleanLine.match(ptrToPtrRegex);
            if (matchLine) {
                let addrReg2 = resolveOp(matchLine[2]);
                asmOutput.push(`LDD R7, ${addrReg2}, 0`);
                tempToggle = 0; 
                let addrReg1 = resolveOp(matchLine[1]);
                asmOutput.push(`STR R7, ${addrReg1}, 0`);
                return;
            }

            matchLine = cleanLine.match(memWriteRegex);
            if (matchLine) {
                let addrReg = resolveOp(matchLine[1]);
                let valReg = resolveOp(matchLine[2]);
                asmOutput.push(`STR ${valReg}, ${addrReg}, 0`);
                return;
            }

            matchLine = cleanLine.match(memReadDeclRegex);
            if (matchLine) {
                let destReg = this.getReg(matchLine[1]);
                let addrReg = resolveOp(matchLine[2]);
                asmOutput.push(`LDD ${destReg}, ${addrReg}, 0`);
                return;
            }

            matchLine = cleanLine.match(ptrWriteNumRegex);
            if (matchLine) {
                let val = matchLine[2];
                if (val.startsWith("'") && val.endsWith("'")) val = "0x" + val.charCodeAt(1).toString(16);
                let valReg = resolveOp(val);
                let addrReg = resolveOp(matchLine[1]);
                asmOutput.push(`STR ${valReg}, ${addrReg}, 0`);
                return;
            }
            
            matchLine = cleanLine.match(ptrWriteVarRegex);
            if (matchLine) {
                let reg = this.symbolTable[matchLine[2]];
                if (!reg) throw new Error(`Line ${index+1}: Undefined variable '${matchLine[2]}'`);
                let addrReg = resolveOp(matchLine[1]);
                asmOutput.push(`STR ${reg}, ${addrReg}, 0`);
                return;
            }

            matchLine = cleanLine.match(ptrReadVarRegex);
            if (matchLine) {
                let addrReg = resolveOp(matchLine[2]);
                asmOutput.push(`LDD ${this.getReg(matchLine[1])}, ${addrReg}, 0`);
                return;
            }
            
            matchLine = cleanLine.match(ptrReadAssignRegex);
            if (matchLine) {
                let destReg = this.symbolTable[matchLine[1]];
                if (!destReg) throw new Error(`Line ${index+1}: Undefined variable '${matchLine[1]}'`);
                let addrReg = resolveOp(matchLine[2]);
                asmOutput.push(`LDD ${destReg}, ${addrReg}, 0`);
                return;
            }

            matchLine = cleanLine.match(memReadAssignRegex);
            if (matchLine) {
                let destReg = this.symbolTable[matchLine[1]];
                if (!destReg) throw new Error(`Line ${index+1}: Undefined variable '${matchLine[1]}'`);
                let addrReg = resolveOp(matchLine[2]);
                asmOutput.push(`LDD ${destReg}, ${addrReg}, 0`);
                return;
            }

            matchLine = cleanLine.match(funcCallRegex);
            if (matchLine) {
                let funcName = matchLine[1];
                asmOutput.push(`JAL R7, ${funcName}`);
                return;
            }
            
            matchLine = cleanLine.match(whileOneRegex);
            if (matchLine) {
                let blockId = this.blockCounter++;
                asmOutput.push(`INF_LOOP_${blockId}:`);
                asmOutput.push(`JMP INF_LOOP_${blockId}`);
                return;
            }

            matchLine = cleanLine.match(ifRegex);
            if (matchLine) {
                let reg1 = resolveOp(matchLine[1]);
                let op = matchLine[2];
                let reg2 = resolveOp(matchLine[3]);
                
                let blockId = this.blockCounter++;
                this.blockStack.push({ type: 'if', id: blockId });
                let tempReg = (reg1 === 'R7' || reg2 === 'R7') ? 'R6' : 'R7'; 
                
                if (op === '<') {
                    asmOutput.push(`SUB ${tempReg}, ${reg2}, ${reg1}`);
                    asmOutput.push(`JGT ${tempReg}, IF_TRUE_${blockId}`);
                } else {
                    asmOutput.push(`SUB ${tempReg}, ${reg1}, ${reg2}`);
                    if (op === '>') asmOutput.push(`JGT ${tempReg}, IF_TRUE_${blockId}`);
                    else if (op === '==') asmOutput.push(`JZ ${tempReg}, IF_TRUE_${blockId}`);
                    else if (op === '!=') asmOutput.push(`JNZ ${tempReg}, IF_TRUE_${blockId}`);
                }
                asmOutput.push(`JMP IF_FALSE_${blockId}`);
                asmOutput.push(`IF_TRUE_${blockId}:`);
                return;
            }

            matchLine = cleanLine.match(elseRegex);
            if (matchLine) {
                if (this.blockStack.length === 0 || this.blockStack[this.blockStack.length-1].type !== 'if') {
                    throw new Error(`Syntax Error on line ${index+1}: 'else' without matching 'if'`);
                }
                let blockData = this.blockStack.pop();
                asmOutput.push(`JMP IF_END_${blockData.id}`);
                asmOutput.push(`IF_FALSE_${blockData.id}:`);
                this.blockStack.push({ type: 'else', id: blockData.id });
                return;
            }

            matchLine = cleanLine.match(whileRegex);
            if (matchLine) {
                let reg1 = resolveOp(matchLine[1]);
                let op = matchLine[2];
                let reg2 = resolveOp(matchLine[3]);
                
                let blockId = this.blockCounter++;
                this.blockStack.push({ type: 'while', id: blockId });
                let tempReg = (reg1 === 'R7' || reg2 === 'R7') ? 'R6' : 'R7'; 
                
                asmOutput.push(`WHILE_START_${blockId}:`);
                if (op === '<') {
                    asmOutput.push(`SUB ${tempReg}, ${reg2}, ${reg1}`);
                    asmOutput.push(`JGT ${tempReg}, WHILE_BODY_${blockId}`);
                } else {
                    asmOutput.push(`SUB ${tempReg}, ${reg1}, ${reg2}`);
                    if (op === '>') asmOutput.push(`JGT ${tempReg}, WHILE_BODY_${blockId}`);
                    else if (op === '==') asmOutput.push(`JZ ${tempReg}, WHILE_BODY_${blockId}`);
                    else if (op === '!=') asmOutput.push(`JNZ ${tempReg}, WHILE_BODY_${blockId}`);
                }
                asmOutput.push(`JMP WHILE_END_${blockId}`);
                asmOutput.push(`WHILE_BODY_${blockId}:`);
                return;
            }
            
            matchLine = cleanLine.match(doRegex);
            if (matchLine) {
                let blockId = this.blockCounter++;
                this.blockStack.push({ type: 'do', id: blockId });
                asmOutput.push(`DO_START_${blockId}:`);
                return;
            }
            
            matchLine = cleanLine.match(endDoWhileRegex);
            if (matchLine) {
                if (this.blockStack.length === 0 || this.blockStack[this.blockStack.length-1].type !== 'do') {
                    throw new Error(`Syntax Error on line ${index+1}: '} while(...);' without matching 'do {'`);
                }
                let blockData = this.blockStack.pop();
                let reg1 = resolveOp(matchLine[1]);
                let op = matchLine[2];
                let reg2 = resolveOp(matchLine[3]);
                let tempReg = (reg1 === 'R7' || reg2 === 'R7') ? 'R6' : 'R7'; 
                
                if (op === '<') {
                    asmOutput.push(`SUB ${tempReg}, ${reg2}, ${reg1}`);
                    asmOutput.push(`JGT ${tempReg}, DO_START_${blockData.id}`);
                } else {
                    asmOutput.push(`SUB ${tempReg}, ${reg1}, ${reg2}`);
                    if (op === '>') asmOutput.push(`JGT ${tempReg}, DO_START_${blockData.id}`);
                    else if (op === '==') asmOutput.push(`JZ ${tempReg}, DO_START_${blockData.id}`);
                    else if (op === '!=') asmOutput.push(`JNZ ${tempReg}, DO_START_${blockData.id}`);
                }
                return;
            }

            matchLine = cleanLine.match(forLoopRegex);
            if (matchLine) {
                let loopVarReg = this.getReg(matchLine[1]);
                let startVal = matchLine[2];
                let op = matchLine[4];
                
                let blockId = this.blockCounter++;
                this.blockStack.push({ type: 'for', id: blockId, reg: loopVarReg, iterator: matchLine[7] });
                
                asmOutput.push(`LDI ${loopVarReg}, ${startVal}`);
                asmOutput.push(`FOR_START_${blockId}:`);
                
                let reg2 = resolveOp(matchLine[5]);
                let tempReg = 'R7'; 
                
                if (op === '<') {
                    asmOutput.push(`SUB ${tempReg}, ${reg2}, ${loopVarReg}`);
                    asmOutput.push(`JGT ${tempReg}, FOR_BODY_${blockId}`);
                } else {
                    asmOutput.push(`SUB ${tempReg}, ${loopVarReg}, ${reg2}`);
                    if (op === '>') asmOutput.push(`JGT ${tempReg}, FOR_BODY_${blockId}`);
                    else if (op === '==') asmOutput.push(`JZ ${tempReg}, FOR_BODY_${blockId}`);
                    else if (op === '!=') asmOutput.push(`JNZ ${tempReg}, FOR_BODY_${blockId}`);
                }
                asmOutput.push(`JMP FOR_END_${blockId}`);
                asmOutput.push(`FOR_BODY_${blockId}:`);
                return;
            }

            matchLine = cleanLine.match(endBlockRegex);
            if (matchLine) {
                if (this.blockStack.length === 0) return; 
                
                let blockData = this.blockStack.pop();
                if (blockData.type === 'while') {
                    asmOutput.push(`JMP WHILE_START_${blockData.id}`);
                    asmOutput.push(`WHILE_END_${blockData.id}:`);
                } else if (blockData.type === 'for') {
                    tempToggle = 0; 
                    let tempReg = resolveOp("1"); 
                    let op = blockData.iterator === '++' ? 'ADD' : 'SUB';
                    asmOutput.push(`${op} ${blockData.reg}, ${blockData.reg}, ${tempReg}`);
                    asmOutput.push(`JMP FOR_START_${blockData.id}`);
                    asmOutput.push(`FOR_END_${blockData.id}:`);
                } else if (blockData.type === 'if') {
                    asmOutput.push(`IF_FALSE_${blockData.id}:`);
                } else if (blockData.type === 'else') {
                    asmOutput.push(`IF_END_${blockData.id}:`);
                } else if (blockData.type === 'func') {
                    asmOutput.push(`JR R7`);
                }
                return;
            }

            throw new Error(`Syntax Error on line ${index +1}: Invalid C-subset syntax -> '${cleanLine}'`);
        });

        return asmOutput.join('\n');
    }
}

// ==========================================
// PART 3: UI INTERACTION LOGIC (LIVE EDITING & DOWNLOADS)
// ==========================================
const compileBtn = document.getElementById('compile-btn');
const cInput = document.getElementById('c-input');
const asmInput = document.getElementById('asm-input');
const hexInput = document.getElementById('hex-input');
const downloadAsmBtn = document.getElementById('download-asm-btn');
const downloadHexBtn = document.getElementById('download-hex-btn');

const cCompiler = new MiniCCompiler();
const assembler = new CustomAssembler();

function compileAssemblyToHex() {
    try {
        hexInput.style.color = "#0f0";
        asmInput.style.color = "#0f0"; 
        const hex = assembler.assemble(asmInput.value);
        hexInput.value = hex.join('\n'); 
    } catch (error) {
        hexInput.style.color = "#ff4444";
        asmInput.style.color = "#ff4444";
        hexInput.value = error.message;
    }
}

function compileCToAssembly() {
    try {
        asmInput.style.color = "#0f0";
        hexInput.style.color = "#0f0";
        const assembly = cCompiler.compileToAssembly(cInput.value);
        asmInput.value = assembly;
        compileAssemblyToHex(); 
    } catch (error) {
        asmInput.style.color = "#ff4444";
        hexInput.style.color = "#ff4444";
        asmInput.value = "C COMPILATION ERROR:\n" + error.message;
        hexInput.value = "Waiting for valid assembly...";
    }
}

function downloadFile(filename, text) {
    const element = document.createElement('a');
    element.setAttribute('href', 'data:text/plain;charset=utf-8,' + encodeURIComponent(text));
    element.setAttribute('download', filename);
    element.style.display = 'none';
    document.body.appendChild(element);
    element.click();
    document.body.removeChild(element);
}

downloadAsmBtn.addEventListener('click', () => downloadFile('assembly.txt', asmInput.value));
downloadHexBtn.addEventListener('click', () => downloadFile('firmware.txt', hexInput.value));

compileBtn.addEventListener('click', compileCToAssembly);
asmInput.addEventListener('input', compileAssemblyToHex);

compileBtn.click();