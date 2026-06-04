module control_unit(

    input  [3:0] opcode,

    output reg       reg_write,
    output reg       mem_read,
    output reg       mem_write,
    output reg       alu_src, // alue input b, 1 for imm value and 0 for reg value
    output reg       wb_sel, //for alu result (0) or mem data (1)
    output reg       branch,
    output reg       jump,

    output reg [3:0] alu_op

);

always @(*) begin

    // Default values
    reg_write = 1'b0;
    mem_read  = 1'b0;
    mem_write = 1'b0;
    alu_src   = 1'b0;
    wb_sel    = 1'b0;
    branch    = 1'b0;
    jump      = 1'b0;
    alu_op    = 4'b0000;

    case(opcode)

        // LDIMM
        4'b0000: begin
            reg_write = 1'b1;
            alu_op    = 4'b1011;   // PASS
            alu_src   = 1'b1;      // immediate
        end

        // ADD
        4'b0001: begin
            reg_write = 1'b1;
            alu_op    = 4'b0000;
        end

        // ADDS
        4'b0010: begin
            reg_write = 1'b1;
            alu_op    = 4'b0001;
        end

        // SUB
        4'b0011: begin
            reg_write = 1'b1;
            alu_op    = 4'b0010;
        end

        // SUBS
        4'b0100: begin
            reg_write = 1'b1;
            alu_op    = 4'b0011;
        end

        // SHL
        4'b0101: begin
            reg_write = 1'b1;
            alu_op    = 4'b0100;
        end

        // SHR
        4'b0110: begin
            reg_write = 1'b1;
            alu_op    = 4'b0101;
        end

        // SAR
        4'b0111: begin
            reg_write = 1'b1;
            alu_op    = 4'b0110;
        end

        // AND
        4'b1000: begin
            reg_write = 1'b1;
            alu_op    = 4'b0111;
        end

        // OR
        4'b1001: begin
            reg_write = 1'b1;
            alu_op    = 4'b1000;
        end

        // XOR
        4'b1010: begin
            reg_write = 1'b1;
            alu_op    = 4'b1001;
        end

        // LOAD
        4'b1011: begin
            reg_write = 1'b1;
            mem_read  = 1'b1;
            wb_sel    = 1'b1;      // memory -> register
            alu_src   = 1'b1;      // base + offset
            alu_op    = 4'b0000;   // ADD
        end

        // STORE
        4'b1100: begin
            mem_write = 1'b1;
            alu_src   = 1'b1;      // base + offset
            alu_op    = 4'b0000;   // ADD
        end

        // BEQ
        4'b1101: begin
            branch = 1'b1;
            alu_op = 4'b0010;      // SUB for comparison
        end

        // BNE
        4'b1110: begin
            branch = 1'b1;
            alu_op = 4'b0010;      // SUB for comparison
        end

        // JMP
        4'b1111: begin
            jump = 1'b1;
        end

    endcase

end

endmodule
