// --- 1. Array Initialization ---
LDI r1, 10        // r1 = p1 = 10 (Outer pointer / Base address)
LDI r2, 13        // r2 = End address (10 + n)
LDI r0, 0         // r0 = 0 (Used for copies)

LDI r5, 5
STORE r5, r1, 0   // *(p1+0) = 5
LDI r5, 8
STORE r5, r1, 1   // *(p1+1) = 8
LDI r5, 2
STORE r5, r1, 2   // *(p1+2) = 2

// --- 2. Outer Loop (p1 < End) ---
OUTER_LOOP:
SUB r7, r2, r1    // r7 = End - p1
BGT r7, OUTER_BODY
JMP END

OUTER_BODY:
ADD r3, r1, r0    // r3 = p2 = p1 (Inner pointer starts at p1)

// --- 3. Inner Loop (p2 < End) ---
INNER_LOOP:
SUB r7, r2, r3    // r7 = End - p2
BGT r7, INNER_BODY
JMP OUTER_INC

INNER_BODY:
LOAD r5, r1, 0    // r5 = *p1
LOAD r6, r3, 0    // r6 = *p2

SUB r7, r5, r6    // *p1 - *p2
BGT r7, SWAP      // If *p1 > *p2, swap
JMP INNER_INC

// --- 4. Swap Logic ---
SWAP:
STORE r5, r3, 0   // *p2 = old *p1
STORE r6, r1, 0   // *p1 = old *p2

// --- 5. Loop Increments ---
INNER_INC:
ADDI r3, r3, 1    // p2++
JMP INNER_LOOP

OUTER_INC:
ADDI r1, r1, 1    // p1++
JMP OUTER_LOOP

// --- 6. Halt ---
END:
HLT
