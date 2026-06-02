// ============================================================
//  alu.v  —  8-bit ALU for the Pipelined Microprocessor
//  IIT Indore | Hardware Design Challenge
//
//  Supported operations (alu_op[3:0]):
//    4'b0000  ADD   — unsigned add
//    4'b0001  ADDS  — add and set flags (same result, flags always driven)
//    4'b0010  SUB   — unsigned subtract
//    4'b0011  SUBS  — subtract and set flags
//    4'b0100  SHL   — logical shift left  by 1
//    4'b0101  SHR   — logical shift right by 1
//    4'b0110  SAR   — arithmetic shift right by 1 (sign-extended)
//    4'b0111  AND   — bitwise AND
//    4'b1000  OR    — bitwise OR
//    4'b1001  XOR   — bitwise XOR
//    4'b1010  NOT   — bitwise complement of A (B ignored)
//    4'b1011  PASS  — pass A directly (used for MOV/forwarding)
//    4'b1100  LUI   — load upper immediate: {B[3:0], 4'b0000}
//    (4'b1101..1111 reserved — output 0, flags cleared)
//
//  Flags produced (registered outside; these are combinational):
//    zero     — result == 8'h00
//    carry    — carry-out / borrow-out for ADD/SUB
//    overflow — signed overflow for ADD/SUB
//    negative — result[7] (MSB)
// ============================================================

module alu (
    input  wire [7:0] a,          // Operand A (Rs1 after forwarding mux)
    input  wire [7:0] b,          // Operand B (Rs2 or sign-extended immediate)
    input  wire [3:0] alu_op,     // Operation select from control unit
    output reg  [7:0] result,     // 8-bit ALU result
    output wire       zero,       // Zero flag  (combinational)
    output reg        carry,      // Carry flag (combinational)
    output reg        overflow,   // Overflow flag (combinational)
    output wire       negative    // Negative flag (combinational)
);

    // --------------------------------------------------------
    //  Internal 9-bit wires capture carry/borrow out of bit 7
    // --------------------------------------------------------
    wire [8:0] add_full  = {1'b0, a} + {1'b0, b};
    wire [8:0] sub_full  = {1'b0, a} - {1'b0, b};

    // Signed overflow detection helpers
    //   ADD overflow: operands same sign, result different sign
    //   SUB overflow: a positive, b negative, result negative  (or vice-versa)
    wire add_ov = (~a[7] & ~b[7] & add_full[7]) | (a[7] & b[7] & ~add_full[7]);
    wire sub_ov = (~a[7] &  b[7] & sub_full[7]) | (a[7] & ~b[7] & ~sub_full[7]);

    // --------------------------------------------------------
    //  Combinational result and flag generation
    // --------------------------------------------------------
    always @(*) begin
        // Default — safe fallback
        result   = 8'h00;
        carry    = 1'b0;
        overflow = 1'b0;

        case (alu_op)
            // ---- Arithmetic ----
            4'b0000: begin              // ADD
                result   = add_full[7:0];
                carry    = add_full[8];
                overflow = add_ov;
            end
            4'b0001: begin              // ADDS  (identical, flags always output)
                result   = add_full[7:0];
                carry    = add_full[8];
                overflow = add_ov;
            end
            4'b0010: begin              // SUB
                result   = sub_full[7:0];
                carry    = sub_full[8]; // borrow out
                overflow = sub_ov;
            end
            4'b0011: begin              // SUBS
                result   = sub_full[7:0];
                carry    = sub_full[8];
                overflow = sub_ov;
            end

            // ---- Shifts ----
            4'b0100: begin              // SHL — shift left logical
                result = {a[6:0], 1'b0};
                carry  = a[7];          // MSB shifts into carry
            end
            4'b0101: begin              // SHR — shift right logical
                result = {1'b0, a[7:1]};
                carry  = a[0];          // LSB shifts into carry
            end
            4'b0110: begin              // SAR — shift right arithmetic
                result = {a[7], a[7:1]};
                carry  = a[0];
            end

            // ---- Logical ----
            4'b0111: result = a & b;    // AND
            4'b1000: result = a | b;    // OR
            4'b1001: result = a ^ b;    // XOR
            4'b1010: result = ~a;       // NOT  (B ignored)

            // ---- Data movement ----
            4'b1011: result = a;        // PASS / MOV (forward A unchanged)

            // ---- Load upper immediate ----
            // Places 4-bit field from B into the upper nibble; clears lower
            4'b1100: result = {b[3:0], 4'b0000};

            // ---- Reserved ----
            default: begin
                result   = 8'h00;
                carry    = 1'b0;
                overflow = 1'b0;
            end
        endcase
    end

    // --------------------------------------------------------
    //  Flag outputs derived directly from result
    // --------------------------------------------------------
    assign zero     = (result == 8'h00);
    assign negative = result[7];

endmodule


// ============================================================
//  alu_with_mul.v  —  EX-stage top-level combining ALU + MUL
//
//  The hardware multiplier runs in parallel with the ALU.
//  The result mux selects between ALU result, MUL lower byte,
//  and MAC (Rd + product) based on the op-extended control bits.
//
//  op_sel encoding (driven by control unit in ID stage):
//    2'b00  — ALU result
//    2'b01  — MUL:  result = (a * b)[7:0]
//    2'b10  — MAC:  result = rd_in + (a * b)[7:0]
// ============================================================

module alu_with_mul (
    input  wire [7:0]  a,
    input  wire [7:0]  b,
    input  wire [7:0]  rd_in,      // Current Rd value for MAC accumulate
    input  wire [3:0]  alu_op,
    input  wire [1:0]  op_sel,     // 00=ALU, 01=MUL, 10=MAC
    output wire [7:0]  result,
    output wire        zero,
    output wire        carry,
    output wire        overflow,
    output wire        negative,
    output wire [15:0] mul_product  // Full 16-bit product (for debug / extension)
);

    // ALU instance
    wire [7:0] alu_result;
    wire       alu_carry, alu_overflow;
    wire       alu_zero,  alu_negative;

    alu u_alu (
        .a        (a),
        .b        (b),
        .alu_op   (alu_op),
        .result   (alu_result),
        .zero     (alu_zero),
        .carry    (alu_carry),
        .overflow (alu_overflow),
        .negative (alu_negative)
    );

    // ---- Combinational 8x8 multiplier ----
    assign mul_product = a * b;          // Vivado infers DSP48 automatically

    // ---- MUL / MAC result ----
    wire [7:0] mul_result = mul_product[7:0];
    wire [7:0] mac_result = rd_in + mul_product[7:0];

    // ---- Result mux ----
    assign result = (op_sel == 2'b01) ? mul_result :
                    (op_sel == 2'b10) ? mac_result  :
                                        alu_result;

    // Flags are only meaningful for ALU operations
    assign zero     = (op_sel == 2'b00) ? alu_zero     : (result == 8'h00);
    assign carry    = (op_sel == 2'b00) ? alu_carry    : 1'b0;
    assign overflow = (op_sel == 2'b00) ? alu_overflow : 1'b0;
    assign negative = result[7];

endmodule
