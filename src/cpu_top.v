module cpu_top(

    input clk,
    input rst

);

    //========================================================
    // Internal Wires
    //========================================================

    wire [7:0] pc;
    wire [15:0] instr;

    wire [3:0] opcode;
    wire [2:0] rd;
    wire [2:0] rs1;
    wire [2:0] rs2;

    wire reg_write;
    wire mem_read;
    wire mem_write;
    wire alu_src;
    wire wb_sel;
    wire branch;
    wire jump;

    wire [3:0] alu_op;

    wire [7:0] rd1;
    wire [7:0] rd2;

    wire [7:0] imm5_ext;
    wire [7:0] imm8;
    wire [7:0] alu_immediate;

    wire [7:0] alu_b;
    wire [7:0] alu_result;

    wire [7:0] mem_data;
    wire [7:0] write_back_data;

    wire zero;
    wire carry;
    wire overflow;
    wire negative;

    wire [7:0] next_pc;

    //========================================================
    // Instruction Decode
    //========================================================

    assign opcode = instr[14:11];

    assign rd  = instr[10:8];
    assign rs1 = instr[7:5];
    assign rs2 = instr[4:2];

    //========================================================
    // PC Logic
    //========================================================

    //assign next_pc = pc + 8'd1; didnt accout for brnach and jump
    //
    wire [7:0] branch_pc  = pc + imm5_ext;       // relative branch target
    wire       take_branch = branch & ((opcode == 4'b1101) ?  zero   // BEQ
                                     : (opcode == 4'b1110) ? ~zero   // BNE
                                     : 1'b0);
    wire [7:0] jump_pc    = {rd1[7:0]};           // JMP: absolute via register
    
    assign next_pc = jump   ? jump_pc   :
                     take_branch ? branch_pc :
                     pc + 8'd1;
    //

    prog_counter PC(

        .clk(clk),
        .rst(rst),

        .next_pc(next_pc),

        .pc(pc)

    );

    //========================================================
    // Instruction Memory
    //========================================================

    instr_mem IMEM(

        .addr(pc),

        .instr(instr)

    );

    //========================================================
    // Control Unit
    //========================================================

    control_unit CU(

        .opcode(opcode),

        .reg_write(reg_write),
        .mem_read(mem_read),
        .mem_write(mem_write),

        .alu_src(alu_src),
        .wb_sel(wb_sel),

        .branch(branch),
        .jump(jump),

        .alu_op(alu_op)

    );

    //========================================================
    // Register File
    //========================================================

    reg_file RF(

        .clk(clk),
        .rst(rst), //jp

        .rs1(rs1),
        .rs2(rs2),

        .rd(rd),

        .wd(write_back_data),

        .reg_write(reg_write),

        .rd1(rd1),
        .rd2(rd2)

    );

    //========================================================
    // Immediate Handling
    //========================================================

    assign imm8 = instr[7:0];

    imm_ext IMM_EXT(

        .imm(instr[4:0]), // issue  ###########

        .imm_ext(imm5_ext)

    );

    assign alu_immediate =
            (opcode == 4'b0000) ?
                imm8 :
                imm5_ext;

    //========================================================
    // ALU Input Mux
    //========================================================

    assign alu_b =
            (alu_src) ?
                alu_immediate :
                rd2;

    //========================================================
    // ALU
    //========================================================

    alu ALU(

        .a(rd1),
        .b(alu_b),

        .alu_op(alu_op),

        .result(alu_result),

        .zero(zero),
        .carry(carry),
        .overflow(overflow),
        .negative(negative)

    );

    //========================================================
    // Data Memory
    //========================================================

    data_mem DMEM(

        .clk(clk),
        .rst(rst),

        .mem_read(mem_read),
        .mem_write(mem_write),

        .addr(alu_result),

        .write_data(rd2),

        .read_data(mem_data)

    );

    //========================================================
    // Writeback Mux
    //========================================================

    assign write_back_data =
            (wb_sel) ?
                mem_data :
                alu_result;

endmodule
