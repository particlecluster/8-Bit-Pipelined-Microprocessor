// --- 1. Array Initialization ---
LDI r0, 0         // r0 = 0 (Used to copy registers later)
LDI r1, 10        // r1 = 10 (Base address of array in memory)

LDI r5, 5         // arr[0] = 5
STORE r5, r1, 0   
LDI r5, 8         // arr[1] = 8
STORE r5, r1, 1   
LDI r5, 2         // arr[2] = 2
STORE r5, r1, 2   

// --- 2. Setup Loop Variables ---
LDI r2, 3         // r2 = n = 3
LDI r3, 0         // r3 = i = 0

// --- 3. Outer Loop (i < n) ---
OUTER_LOOP:
SUB r7, r2, r3    // r7 = n - i
BGT r7, OUTER_BODY // If (n - i) > 0, execute outer loop
JMP END           // Else, finish program

OUTER_BODY:
ADD r4, r3, r0    // r4 = j = i (copies r3 into r4)

// --- 4. Inner Loop (j < n) ---
INNER_LOOP:
SUB r7, r2, r4    // r7 = n - j
BGT r7, INNER_BODY // If (n - j) > 0, execute inner loop
JMP OUTER_INC     // Else, break to outer increment

INNER_BODY:
// Calculate pointer and Load arr[i]
ADD r7, r1, r3    // r7 = base + i
LOAD r5, r7, 0    // r5 = arr[i]

// Calculate pointer and Load arr[j]
ADD r7, r1, r4    // r7 = base + j
LOAD r6, r7, 0    // r6 = arr[j]

// if (arr[i] > arr[j])
SUB r7, r5, r6    // r7 = arr[i] - arr[j]
BGT r7, SWAP      // If arr[i] > arr[j], jump to Swap
JMP INNER_INC     // Else, skip swap

// --- 5. Swap Logic ---
SWAP:
// r5 currently holds arr[i], r6 holds arr[j]
ADD r7, r1, r4    // Point to arr[j]
STORE r5, r7, 0   // arr[j] = old arr[i]

ADD r7, r1, r3    // Point to arr[i]
STORE r6, r7, 0   // arr[i] = old arr[j]

// --- 6. Loop Increments ---
INNER_INC:
ADDI r4, r4, 1    // j++
JMP INNER_LOOP

OUTER_INC:
ADDI r3, r3, 1    // i++
JMP OUTER_LOOP

// --- 7. Halt ---
END:
HLT
