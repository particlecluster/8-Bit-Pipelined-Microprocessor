`timescale 1ns / 1ps
`default_nettype none

// =============================================================================
// CPU_Core_5Stage.v  --  Team elec_03, IIT Indore
// =============================================================================

// -----------------------------------------------------------------------------
// ISA Opcodes
// -----------------------------------------------------------------------------
`define OP_ADD   5'b00000
`define OP_SUB   5'b00001
`define OP_AND   5'b00010
`define OP_OR    5'b00011
`define OP_XOR   5'b00100
`define OP_SHL   5'b00101
`define OP_SHR   5'b00110
`define OP_LDI   5'b00111
`define OP_LDD   5'b01000
`define OP_STR   5'b01001
`define OP_JMP   5'b01010
`define OP_JZ    5'b01011
`define OP_JNZ   5'b01100
`define OP_JGT   5'b01101
`define OP_ADDI  5'b01110
`define OP_SLT   5'b01111
`define OP_MUL   5'b10000
`define OP_MAC   5'b10001
`define OP_ROL   5'b10010
`define OP_ROR   5'b10011
`define OP_RETI  5'b10100
`define OP_STD   5'b10101
`define OP_JAL   5'b10110   
`define OP_JR    5'b10111   
`define OP_TRAP  5'b11000   
`define OP_ERET  5'b11001   
`define OP_MFC0  5'b11010   
`define OP_HALT  5'b11111

// =============================================================================
// TOP MODULE: 5-Stage CPU Core
// =============================================================================
module CPU_Core_5Stage #(
    parameter integer DATA_W     = 8,
    parameter integer ADDR_W     = 8,
    parameter integer INSTR_W    = 16,
    parameter integer OPCODE_W   = 5,
    parameter integer REG_ADDR_W = 3,
    parameter integer IMM5_W     = 5,
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire              clk,
    input  wire              rst,
    input  wire              interrupt_pin,
    input  wire [DATA_W-1:0] external_digital_pins,
    input  wire [DATA_W-1:0] external_adc_pins,
    output wire              motor_pwm_pin,
    input  wire              uart_rx,
    output wire              uart_tx
);

    wire system_rst;

    // =========================================================================
    // PIPELINE REGISTERS
    // =========================================================================

    // -- IF/ID --
    reg [INSTR_W-1:0] IF_ID_instr;
    reg [ADDR_W-1:0]  IF_ID_pc;
    reg               IF_ID_pred_taken;
    reg [ADDR_W-1:0]  IF_ID_fallback_pc;

    // -- ID/EX --
    reg [ADDR_W-1:0]     ID_EX_pc;
    reg [DATA_W-1:0]     ID_EX_rd1, ID_EX_rd2, ID_EX_rd3;
    reg [DATA_W-1:0]     ID_EX_imm, ID_EX_imm5_sext, ID_EX_imm5_zext;
    reg [REG_ADDR_W-1:0] ID_EX_rd_addr, ID_EX_rs1_addr, ID_EX_rs2_addr, ID_EX_rd_in_addr;
    reg [OPCODE_W-1:0]   ID_EX_opcode;
    reg                  ID_EX_reg_we, ID_EX_mem_we, ID_EX_pc_src, ID_EX_halt;
    reg                  ID_EX_base_reg_src, ID_EX_mem_addr_src;
    reg [1:0]            ID_EX_alu_b_src, ID_EX_res_src;
    reg                  ID_EX_pred_taken;
    reg [ADDR_W-1:0]     ID_EX_fallback_pc;

    // -- EX/MEM --
    reg [DATA_W-1:0]     EX_MEM_alu_result, EX_MEM_mem_addr, EX_MEM_store_data, EX_MEM_imm;
    reg [ADDR_W-1:0]     EX_MEM_fallback_pc; 
    reg [REG_ADDR_W-1:0] EX_MEM_rd_addr;
    reg                  EX_MEM_reg_we, EX_MEM_mem_we;
    reg [1:0]            EX_MEM_res_src;

    // -- MEM/WB --
    reg [DATA_W-1:0]     MEM_WB_alu_result, MEM_WB_mem_data, MEM_WB_imm;
    reg [ADDR_W-1:0]     MEM_WB_fallback_pc; 
    reg [REG_ADDR_W-1:0] MEM_WB_rd_addr;
    reg                  MEM_WB_reg_we;
    reg [1:0]            MEM_WB_res_src;

    // =========================================================================
    // SYSTEM CONTROL & WRITE-BACK
    // =========================================================================
    wire [DATA_W-1:0] MEM_WB_reg_write_data =
        (MEM_WB_res_src == 2'b00) ? MEM_WB_alu_result :
        (MEM_WB_res_src == 2'b01) ? MEM_WB_mem_data   :
        (MEM_WB_res_src == 2'b10) ? MEM_WB_imm        : MEM_WB_fallback_pc;

    ResetSynchronizer u_RstSync (
        .clk(clk), 
        .async_rst_in(rst), 
        .sync_rst_out(system_rst)
    );

    // =========================================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // =========================================================================
    wire [ADDR_W-1:0]  pc_if, next_pc_if;
    wire [INSTR_W-1:0] instr_if;
    wire               predict_taken_if, trigger_int;
    wire [ADDR_W-1:0]  epc;
    
    wire reti_taken_ex, is_branch_instr_ex, branch_taken_ex, ex_mispredict;
    wire [ADDR_W-1:0] actual_target_ex, ex_recovery_pc;

    wire              exception_taken;
    wire [ADDR_W-1:0] exception_vector_pc;
    wire [ADDR_W-1:0] exception_epc;
    wire [1:0]        exception_cause;
    wire              in_exception;
    wire              eret_taken_ex = (ID_EX_opcode == `OP_ERET);
    wire [ADDR_W-1:0] return_epc    = in_exception ? exception_epc : epc;

    InterruptController #(.ADDR_W(ADDR_W)) u_IntCtrl (
        .clk(clk),                      .rst(system_rst), 
        .interrupt_pin(interrupt_pin),  .reti_taken(reti_taken_ex), 
        .ex_mispredict(ex_mispredict),  .ex_recovery_pc(ex_recovery_pc), 
        .IF_ID_pc(IF_ID_pc),            .trigger_int(trigger_int), 
        .epc(epc)
    );

    BranchPredictor #(.ADDR_W(ADDR_W)) u_BP (
        .clk(clk),                          .rst(system_rst), 
        .pc(pc_if),                         .pc_plus_1(pc_if + 1'b1),
        .trigger_int(trigger_int),          .ex_is_branch(is_branch_instr_ex),
        .ex_pc(ID_EX_pc),                   .ex_actual_target(actual_target_ex),
        .ex_branch_taken(branch_taken_ex),  .ex_mispredict(ex_mispredict),
        .ex_recovery_pc(ex_recovery_pc),    .next_pc(next_pc_if),
        .predict_taken(predict_taken_if)
    );

    ProgramCounter #(.ADDR_W(ADDR_W)) u_PC (
        .clk(clk), 
        .rst(system_rst),
        // An accepted interrupt must redirect the PC even when decode has
        // requested a load-use hold; otherwise the one-cycle request is lost.
        .halt(ID_EX_halt || (load_use_hazard && !trigger_int)),
        .next_pc(exception_taken ? exception_vector_pc : next_pc_if),
        .pc(pc_if)
    );

    InstructionMemory #(.ADDR_W(ADDR_W), .INSTR_W(INSTR_W)) u_IMEM (
        .pc(pc_if), 
        .instr(instr_if)
    );

    always @(posedge clk) begin
        if (system_rst || ex_mispredict || trigger_int || exception_taken) begin
            IF_ID_instr       <= {INSTR_W{1'b0}}; 
            IF_ID_pc          <= {ADDR_W{1'b0}};
            IF_ID_pred_taken  <= 1'b0; 
            IF_ID_fallback_pc <= {ADDR_W{1'b0}};
        end else if (!load_use_hazard) begin
            IF_ID_instr       <= instr_if; 
            IF_ID_pc          <= pc_if;
            IF_ID_pred_taken  <= predict_taken_if; 
            IF_ID_fallback_pc <= pc_if + 1'b1;
        end
    end

    // =========================================================================
    // STAGE 2: INSTRUCTION DECODE (ID)
    // =========================================================================
    wire [OPCODE_W-1:0]   opcode_id  = IF_ID_instr[15:11];
    wire [DATA_W-1:0]     imm_id     = IF_ID_instr[7:0];
    wire [REG_ADDR_W-1:0] rd_addr_id = IF_ID_instr[10:8];
    wire reg_we_id, mem_we_id, pc_src_id, rs1_src_id, rs2_src_id, halt_id;
    wire base_reg_src_id, mem_addr_src_id;
    wire [1:0] alu_b_src_id, res_src_id;

    ControlUnit #(.OPCODE_W(OPCODE_W)) u_CU (
        .opcode(opcode_id),              .zero(1'b0),                     .greater(1'b0),
        .reg_we(reg_we_id),              .mem_we(mem_we_id),              .alu_b_src(alu_b_src_id),
        .res_src(res_src_id),            .pc_src(pc_src_id),              .rs1_src(rs1_src_id),
        .rs2_src(rs2_src_id),            .mem_addr_src(mem_addr_src_id),  .base_reg_src(base_reg_src_id), 
        .halt(halt_id)
    );

    wire [REG_ADDR_W-1:0] read_reg_1_id = rs1_src_id ? rd_addr_id       : IF_ID_instr[7:5];
    wire [REG_ADDR_W-1:0] read_reg_2_id = rs2_src_id ? IF_ID_instr[7:5] : IF_ID_instr[4:2];
    wire [DATA_W-1:0]     reg_rd1_id, reg_rd2_id, reg_rd3_id;

    RegisterFile #(.DATA_W(DATA_W), .REG_ADDR_W(REG_ADDR_W)) u_RegFile (
        .clk(clk),                       .we(MEM_WB_reg_we),
        .rs1(read_reg_1_id),             .rs2(read_reg_2_id),             .rs3(rd_addr_id),
        .wa(MEM_WB_rd_addr),             .wd(MEM_WB_reg_write_data),
        .rd1(reg_rd1_id),                .rd2(reg_rd2_id),                .rd3(reg_rd3_id)
    );

    wire [DATA_W-1:0] imm5_sext_id, imm5_zext_id;
    Extender #(.DATA_W(DATA_W), .IMM5_W(IMM5_W)) u_EXT (
        .imm5(imm_id[IMM5_W-1:0]), 
        .imm5_sext(imm5_sext_id), 
        .imm5_zext(imm5_zext_id)
    );

    wire id_alu_two_source = (opcode_id <= `OP_SHR) || (opcode_id == `OP_SLT) ||
                             ((opcode_id >= `OP_MUL) && (opcode_id <= `OP_ROR)) ||
                             (opcode_id == `OP_STR);
                             
    wire opcode_valid_id = (opcode_id <= `OP_JR) || (opcode_id == `OP_RETI) ||
                           (opcode_id == `OP_TRAP) || 
                           (opcode_id == `OP_ERET) || (opcode_id == `OP_MFC0) || 
                           (opcode_id == `OP_HALT);
    wire illegal_inst_id = !opcode_valid_id;
    wire trap_id         = (opcode_id == `OP_TRAP);

    wire id_uses_rs1  = !(opcode_id == `OP_LDI || opcode_id == `OP_LDD ||
                          opcode_id == `OP_JMP || opcode_id == `OP_JAL ||
                          opcode_id == `OP_RETI || opcode_id == `OP_HALT ||
                          opcode_id == `OP_TRAP || opcode_id == `OP_ERET ||
                          opcode_id == `OP_MFC0);

    wire id_uses_rd3     = (opcode_id == `OP_MAC);
    
    wire load_use_hazard = ID_EX_reg_we && (ID_EX_res_src == 2'b01) &&
        (ID_EX_rd_addr != {REG_ADDR_W{1'b0}}) &&
        ((id_uses_rs1 && (ID_EX_rd_addr == read_reg_1_id)) ||
         (id_alu_two_source && (ID_EX_rd_addr == read_reg_2_id)) ||
         (id_uses_rd3 && (ID_EX_rd_addr == rd_addr_id)));

    always @(posedge clk) begin
        if (system_rst || ex_mispredict || trigger_int || load_use_hazard || exception_taken) begin
            ID_EX_reg_we       <= 1'b0; 
            ID_EX_mem_we       <= 1'b0; 
            ID_EX_pc_src       <= 1'b0;
            ID_EX_halt         <= 1'b0; 
            ID_EX_opcode       <= {OPCODE_W{1'b0}}; 
            ID_EX_pred_taken   <= 1'b0;
        end else begin
            ID_EX_pc           <= IF_ID_pc; 
            ID_EX_rd1          <= reg_rd1_id; 
            ID_EX_rd2          <= reg_rd2_id; 
            ID_EX_rd3          <= reg_rd3_id;
            ID_EX_imm          <= imm_id; 
            ID_EX_imm5_sext    <= imm5_sext_id; 
            ID_EX_imm5_zext    <= imm5_zext_id;
            ID_EX_rd_addr      <= rd_addr_id; 
            ID_EX_opcode       <= opcode_id;
            ID_EX_rs1_addr     <= read_reg_1_id; 
            ID_EX_rs2_addr     <= read_reg_2_id; 
            ID_EX_rd_in_addr   <= rd_addr_id;
            ID_EX_reg_we       <= reg_we_id; 
            ID_EX_mem_we       <= mem_we_id; 
            ID_EX_pc_src       <= pc_src_id; 
            ID_EX_halt         <= halt_id;
            ID_EX_base_reg_src <= base_reg_src_id; 
            ID_EX_mem_addr_src <= mem_addr_src_id;
            ID_EX_alu_b_src    <= alu_b_src_id; 
            ID_EX_res_src      <= res_src_id;
            ID_EX_pred_taken   <= IF_ID_pred_taken; 
            ID_EX_fallback_pc  <= IF_ID_fallback_pc;
        end
    end

    // =========================================================================
    // STAGE 3: EXECUTE (EX)
    // =========================================================================
    wire [DATA_W-1:0] fwd_rd1_ex, fwd_rd2_ex, fwd_rd3_ex;
    
    ForwardingUnit #(.DATA_W(DATA_W), .REG_ADDR_W(REG_ADDR_W)) u_FWD (
        .EX_MEM_reg_we(EX_MEM_reg_we),           .EX_MEM_rd_addr(EX_MEM_rd_addr),
        .EX_MEM_res_src(EX_MEM_res_src),         .EX_MEM_alu_result(EX_MEM_alu_result),
        .EX_MEM_imm(EX_MEM_imm),                 .MEM_WB_reg_we(MEM_WB_reg_we), 
        .MEM_WB_rd_addr(MEM_WB_rd_addr),         .MEM_WB_reg_write_data(MEM_WB_reg_write_data),
        .ID_EX_rs1_addr(ID_EX_rs1_addr),         .ID_EX_rs2_addr(ID_EX_rs2_addr),
        .ID_EX_rd_in_addr(ID_EX_rd_in_addr),     .ID_EX_rd1(ID_EX_rd1), 
        .ID_EX_rd2(ID_EX_rd2),                   .ID_EX_rd3(ID_EX_rd3),
        .fwd_rd1(fwd_rd1_ex),                    .fwd_rd2(fwd_rd2_ex), 
        .fwd_rd3(fwd_rd3_ex)
    );

    wire [DATA_W-1:0] alu_b_in_ex = (ID_EX_alu_b_src == 2'b00) ? fwd_rd2_ex :
                                    (ID_EX_alu_b_src == 2'b01) ? {DATA_W{1'b0}} : ID_EX_imm5_sext;
                                    
    wire [DATA_W-1:0] alu_result_ex; 
    wire zero_ex, greater_ex;

    ALU #(.DATA_W(DATA_W), .OPCODE_W(OPCODE_W)) u_ALU (
        .a(fwd_rd1_ex),            .b(alu_b_in_ex), 
        .rd_val(fwd_rd3_ex),       .alu_control(ID_EX_opcode),
        .result(alu_result_ex),    .zero(zero_ex), 
        .greater(greater_ex)
    );

    wire [DATA_W:0] add_extended_ex = {1'b0, fwd_rd1_ex} + {1'b0, alu_b_in_ex};
    wire alu_overflow_ex = (ID_EX_reg_we && (ID_EX_opcode == `OP_ADD || ID_EX_opcode == `OP_ADDI) && add_extended_ex[DATA_W]);

    Exception_Unit #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W)
    ) u_CP0 (
        .clk(clk),                       .rst(system_rst),
        .id_illegal_inst(illegal_inst_id), .id_trap(trap_id),
        .ex_overflow(alu_overflow_ex),   .eret_taken(eret_taken_ex),
        .if_pc(IF_ID_pc),                .ex_pc(ID_EX_pc),
        .exception_taken(exception_taken),
        .exception_vector_pc(exception_vector_pc),
        .exception_epc(exception_epc),   .exception_cause(exception_cause),
        .in_exception(in_exception)
    );

    wire [DATA_W-1:0] alu_result_with_cp0_ex = (ID_EX_opcode == `OP_MFC0) ?
        (ID_EX_imm[0] ? exception_epc : {{(DATA_W-2){1'b0}}, exception_cause}) : alu_result_ex;

    wire [DATA_W-1:0] base_reg_ex = ID_EX_base_reg_src ? fwd_rd2_ex : fwd_rd1_ex;
    wire [DATA_W-1:0] mem_addr_ex = ID_EX_mem_addr_src ? ID_EX_imm : base_reg_ex + ID_EX_imm5_zext;

    BranchResolutionUnit #(.ADDR_W(ADDR_W), .OPCODE_W(OPCODE_W)) u_BRU (
        .ex_pc(ID_EX_pc),                  .opcode(ID_EX_opcode), 
        .pc_src(ID_EX_pc_src),             .zero(zero_ex), 
        .greater(greater_ex),              .pred_taken(ID_EX_pred_taken), 
        .imm(ID_EX_imm),                   .fallback_pc(ID_EX_fallback_pc),
        .reg_target(fwd_rd1_ex),           .reti_taken(reti_taken_ex), 
        .is_branch_instr(is_branch_instr_ex), .branch_taken(branch_taken_ex),
        .epc(return_epc),                  .actual_target(actual_target_ex),  
        .ex_mispredict(ex_mispredict),     .ex_recovery_pc(ex_recovery_pc)
    );

    always @(posedge clk) begin
        if (system_rst || alu_overflow_ex) begin 
            EX_MEM_reg_we <= 1'b0; 
            EX_MEM_mem_we <= 1'b0; 
        end else begin
            EX_MEM_alu_result  <= alu_result_with_cp0_ex;
            EX_MEM_mem_addr    <= mem_addr_ex; 
            EX_MEM_store_data  <= fwd_rd1_ex;
            EX_MEM_imm         <= ID_EX_imm; 
            EX_MEM_fallback_pc <= ID_EX_fallback_pc; 
            EX_MEM_rd_addr     <= ID_EX_rd_addr;
            EX_MEM_reg_we      <= ID_EX_reg_we; 
            EX_MEM_mem_we      <= ID_EX_mem_we; 
            EX_MEM_res_src     <= ID_EX_res_src;
        end
    end

    // =========================================================================
    // STAGE 4: MEMORY (MEM)
    // =========================================================================
    wire [DATA_W-1:0] mem_rd_mem;
    wire [DATA_W-1:0] motor_duty_cycle_mem;
    wire [DATA_W-1:0] uart_rx_data_mem;
    wire [DATA_W-1:0] uart_status_mem;
    wire uart_rx_read_mem = !EX_MEM_mem_we && (EX_MEM_mem_addr == 8'hFB);
    wire uart_tx_write_mem = EX_MEM_mem_we && (EX_MEM_mem_addr == 8'hFC);

    UART_Peripheral #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_UART (
        .clk(clk),
        .rst(system_rst),
        .rx(uart_rx),
        .tx(uart_tx),
        .tx_write(uart_tx_write_mem),
        .tx_data(EX_MEM_store_data),
        .rx_read(uart_rx_read_mem),
        .rx_data(uart_rx_data_mem),
        .status(uart_status_mem)
    );
    
    DataMemory_UART #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_DMEM (
        .clk(clk),                               .we(EX_MEM_mem_we), 
        .addr(EX_MEM_mem_addr),                  .wd(EX_MEM_store_data),
        .digital_in(external_digital_pins),      .adc_in(external_adc_pins),
        .uart_rx_data(uart_rx_data_mem),         .uart_status(uart_status_mem),
        .rd(mem_rd_mem),                         .pwm_duty_cycle(motor_duty_cycle_mem)
    );

    always @(posedge clk) begin
        if (system_rst) begin
            MEM_WB_reg_we <= 1'b0;
        end else begin
            MEM_WB_alu_result  <= EX_MEM_alu_result; 
            MEM_WB_mem_data    <= mem_rd_mem; 
            MEM_WB_imm         <= EX_MEM_imm;
            MEM_WB_fallback_pc <= EX_MEM_fallback_pc;
            MEM_WB_rd_addr     <= EX_MEM_rd_addr; 
            MEM_WB_reg_we      <= EX_MEM_reg_we; 
            MEM_WB_res_src     <= EX_MEM_res_src;
        end
    end

    // =========================================================================
    // STAGE 5: WRITE BACK (WB)
    // =========================================================================

    PWM_Generator #(.DATA_W(DATA_W)) u_PWM (
        .clk(clk), 
        .rst(system_rst), 
        .duty_cycle(motor_duty_cycle_mem), 
        .pwm_out(motor_pwm_pin)
    );

endmodule
