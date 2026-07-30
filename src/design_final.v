`define EXCEPTION_V2
`timescale 1ns / 1ps
`default_nettype none
// =============================================================================
// CPU_Core_5Stage.v  --  Team elec_03, IIT Indore
// =============================================================================
// Five-stage pipelined implementation of the elec_03 16-bit RISC ISA.
//
//   Pipeline stages:  IF -> ID -> EX -> MEM -> WB
//
//   ISA summary (5-bit opcode, see OP_* localparams below):
//     ALU (2-operand, register)  : ADD SUB AND OR XOR SHL SHR SLT
//     ALU (advanced)             : MUL MAC ROL ROR
//     Immediate                  : LDI (load imm), ADDI (add imm)
//     Memory                     : LDD (load, base+disp), STR (store, base+disp),
//                                   STD (store, direct/absolute address)
//     Control flow               : JMP JZ JNZ JGT JAL JR RETI HALT
//       JAL : rd <- PC+1 (link) ; PC <- PC + imm8   (subroutine call)
//       JR  : PC <- reg[rs1]                        (subroutine return / computed jump)
//
//   Hazard handling:
//     - Full EX/MEM and MEM/WB forwarding (ForwardingUnit), EX/MEM has priority.
//     - Loads cannot forward out of EX/MEM (data not back from memory yet) ->
//       a single-cycle load-use stall (bubble into EX) is inserted instead.
//     - Static branch prediction with a 32-entry direct-mapped BTB + 1-bit BHT
//       (BranchPredictor). Mispredicts are resolved in EX and flush IF/ID + ID/EX.
//       JAL/JR are treated as always-taken branch-class instructions for BTB
//       training purposes (same mispredict/flush/recovery path as JMP).
//
//   Interrupts:
//     - Single external interrupt_pin, rising-edge triggered, non-nested.
//     - InterruptController latches the return PC (epc) and blocks re-entry
//       into the ISR until RETI (opcode OP_RETI) is retired.
//
//   Compile (with the CPU_Core_5Stage top-level and a testbench), e.g.:
//     iverilog -s CPU_Core_5Stage -o sim5 design.v design2.v <testbench>.v
// =============================================================================

// -----------------------------------------------------------------------------
// Shared opcode encodings and datapath widths.
// Included/duplicated at the top of each module that needs them so the file
// stays a single compilation unit; keep this block as the single source of
// truth when adding or renumbering instructions.
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
`define OP_JAL   5'b10110   // NEW (Bonus Task 1): rd <- PC+1, PC <- PC + imm8
`define OP_JR    5'b10111   // NEW (Bonus Task 1): PC <- reg[rs1]
`ifdef EXCEPTION_V2
`define OP_TRAP  5'b11000   // deliberate software exception
`define OP_ERET  5'b11001   // exception return (continues at EPC + 1)
`define OP_MFC0  5'b11010   // rd <- CAUSE (imm=0) or EPC (imm=1)
`endif
`define OP_HALT  5'b11111

module CPU_Core_5Stage #(
    parameter integer DATA_W     = 8,   // register / ALU / memory data width
    parameter integer ADDR_W     = 8,   // PC / memory address width
    parameter integer INSTR_W    = 16,  // instruction word width
    parameter integer OPCODE_W   = 5,   // opcode field width
    parameter integer REG_ADDR_W = 3,   // register file address width (8 regs)
    parameter integer IMM5_W     = 5    // short immediate field width
) (
    // -- Clock / Reset --
    input  wire                  clk,
    input  wire                  rst,

    // -- Interrupt Interface --
    input  wire                  interrupt_pin,

    // -- Memory-Mapped Peripheral Interface --
    input  wire [DATA_W-1:0]     external_digital_pins,
    input  wire [DATA_W-1:0]     external_adc_pins,
    output wire                  motor_pwm_pin
);
    // Local opcode aliases (see `OP_* defines above)
    localparam [OPCODE_W-1:0]
        OP_ADD  = `OP_ADD,  OP_SUB  = `OP_SUB,  OP_AND  = `OP_AND,  OP_OR   = `OP_OR,
        OP_XOR  = `OP_XOR,  OP_SHL  = `OP_SHL,  OP_SHR  = `OP_SHR,  OP_LDI  = `OP_LDI,
        OP_LDD  = `OP_LDD,  OP_STR  = `OP_STR,  OP_JMP  = `OP_JMP,  OP_JZ   = `OP_JZ,
        OP_JNZ  = `OP_JNZ,  OP_JGT  = `OP_JGT,  OP_ADDI = `OP_ADDI, OP_SLT  = `OP_SLT,
        OP_MUL  = `OP_MUL,  OP_MAC  = `OP_MAC,  OP_ROL  = `OP_ROL,  OP_ROR  = `OP_ROR,
        OP_RETI = `OP_RETI, OP_STD  = `OP_STD,  OP_JAL  = `OP_JAL,  OP_JR   = `OP_JR,
        OP_HALT = `OP_HALT;

    wire system_rst;

    // -- IF/ID pipeline register --
    reg [INSTR_W-1:0] IF_ID_instr;
    reg [ADDR_W-1:0]  IF_ID_pc;
    reg               IF_ID_pred_taken;
    reg [ADDR_W-1:0]  IF_ID_fallback_pc;

    // -- ID/EX pipeline register --
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

    // -- EX/MEM pipeline register --
    reg [DATA_W-1:0]     EX_MEM_alu_result, EX_MEM_mem_addr, EX_MEM_store_data, EX_MEM_imm;
    reg [ADDR_W-1:0]     EX_MEM_fallback_pc;        // NEW: link value for JAL (PC+1)
    reg [REG_ADDR_W-1:0] EX_MEM_rd_addr;
    reg                  EX_MEM_reg_we, EX_MEM_mem_we;
    reg [1:0]            EX_MEM_res_src;

    // -- MEM/WB pipeline register --
    reg [DATA_W-1:0]     MEM_WB_alu_result, MEM_WB_mem_data, MEM_WB_imm;
    reg [ADDR_W-1:0]     MEM_WB_fallback_pc;        // NEW: link value for JAL (PC+1)
    reg [REG_ADDR_W-1:0] MEM_WB_rd_addr;
    reg                  MEM_WB_reg_we;
    reg [1:0]            MEM_WB_res_src;

    wire [ADDR_W-1:0]  pc_if, next_pc_if;
    wire [INSTR_W-1:0] instr_if;
    wire predict_taken_if, trigger_int;
    wire [ADDR_W-1:0] epc;
    wire reti_taken_ex, is_branch_instr_ex, branch_taken_ex, ex_mispredict;
    wire [ADDR_W-1:0] actual_target_ex, ex_recovery_pc;

`ifdef EXCEPTION_V2
    // Exception Control Unit state.  These registers are intentionally kept
    // visible at the CPU hierarchy for waveform-based evaluation.
    localparam [ADDR_W-1:0] EXCEPTION_VECTOR = 8'h80;
    localparam [1:0] CAUSE_OVERFLOW = 2'd1, CAUSE_ILLEGAL = 2'd2, CAUSE_TRAP = 2'd3;
    reg [ADDR_W-1:0] exception_epc;
    reg [1:0]        exception_cause;
    reg              in_exception;
    wire eret_taken_ex = (ID_EX_opcode == `OP_ERET);
    wire [ADDR_W-1:0] return_epc = in_exception ? exception_epc : epc;
`endif

    // Write-back data is also the value forwarded from MEM/WB.
    // res_src: 00=ALU result, 01=loaded memory data, 10=immediate (LDI), 11=link (JAL, PC+1)
    wire [DATA_W-1:0] MEM_WB_reg_write_data =
        (MEM_WB_res_src == 2'b00) ? MEM_WB_alu_result :
        (MEM_WB_res_src == 2'b01) ? MEM_WB_mem_data   :
        (MEM_WB_res_src == 2'b10) ? MEM_WB_imm        : MEM_WB_fallback_pc;

    InterruptController #(.ADDR_W(ADDR_W)) u_IntCtrl (
        .clk(clk), .rst(system_rst), .interrupt_pin(interrupt_pin),
        .reti_taken(reti_taken_ex), .ex_mispredict(ex_mispredict),
        .ex_recovery_pc(ex_recovery_pc), .IF_ID_pc(IF_ID_pc),
        .trigger_int(trigger_int), .epc(epc)
    );
    BranchPredictor #(.ADDR_W(ADDR_W)) u_BP (
        .clk(clk), .rst(system_rst), .pc(pc_if), .pc_plus_1(pc_if + 1'b1),
        .trigger_int(trigger_int), .ex_is_branch(is_branch_instr_ex),
        .ex_pc(ID_EX_pc), .ex_actual_target(actual_target_ex),
        .ex_branch_taken(branch_taken_ex), .ex_mispredict(ex_mispredict),
        .ex_recovery_pc(ex_recovery_pc), .next_pc(next_pc_if),
        .predict_taken(predict_taken_if)
    );

    // ---------------- ID stage ----------------
    wire [OPCODE_W-1:0]   opcode_id  = IF_ID_instr[15:11];
    wire [DATA_W-1:0]     imm_id     = IF_ID_instr[7:0];
    wire [REG_ADDR_W-1:0] rd_addr_id = IF_ID_instr[10:8];
    wire reg_we_id, mem_we_id, pc_src_id, rs1_src_id, rs2_src_id, halt_id;
    wire base_reg_src_id, mem_addr_src_id;
    wire [1:0] alu_b_src_id, res_src_id;
    ControlUnit #(.OPCODE_W(OPCODE_W)) u_CU (.opcode(opcode_id), .zero(1'b0), .greater(1'b0),
        .reg_we(reg_we_id), .mem_we(mem_we_id), .alu_b_src(alu_b_src_id),
        .res_src(res_src_id), .pc_src(pc_src_id), .rs1_src(rs1_src_id),
        .rs2_src(rs2_src_id), .mem_addr_src(mem_addr_src_id),
        .base_reg_src(base_reg_src_id), .halt(halt_id));
`ifdef EXCEPTION_V2
    // Decode-stage faults are caught before they can enter ID/EX.  The
    // explicit list makes every unused 5-bit opcode illegal, including 0xFF.
    wire opcode_valid_id = (opcode_id <= `OP_JR) ||
                           (opcode_id == `OP_TRAP) || (opcode_id == `OP_ERET) ||
                           (opcode_id == `OP_MFC0) || (opcode_id == OP_HALT);
    wire illegal_instruction_id = !opcode_valid_id;
    wire trap_id = (opcode_id == `OP_TRAP);
`endif
    wire [REG_ADDR_W-1:0] read_reg_1_id = rs1_src_id ? rd_addr_id : IF_ID_instr[7:5];
    wire [REG_ADDR_W-1:0] read_reg_2_id = rs2_src_id ? IF_ID_instr[7:5] : IF_ID_instr[4:2];
    wire [DATA_W-1:0] reg_rd1_id, reg_rd2_id, reg_rd3_id;
    RegisterFile #(.DATA_W(DATA_W), .REG_ADDR_W(REG_ADDR_W)) u_RegFile (
        .clk(clk), .we(MEM_WB_reg_we),
        .rs1(read_reg_1_id), .rs2(read_reg_2_id), .rs3(rd_addr_id),
        .wa(MEM_WB_rd_addr), .wd(MEM_WB_reg_write_data),
        .rd1(reg_rd1_id), .rd2(reg_rd2_id), .rd3(reg_rd3_id));
    wire [DATA_W-1:0] imm5_sext_id, imm5_zext_id;
    Extender #(.DATA_W(DATA_W), .IMM5_W(IMM5_W)) u_EXT (
        .imm5(imm_id[IMM5_W-1:0]), .imm5_sext(imm5_sext_id), .imm5_zext(imm5_zext_id));

    // A load's data is available only after MEM.  Hold fetch/decode for one
    // cycle when the instruction in EX is a load and ID consumes its result.
    // NOTE: OP_STR also consumes read_reg_2 as its base address register in
    // EX, so it must be covered here too, not just the ALU ops.
    wire id_alu_two_source = (opcode_id <= OP_SHR) || (opcode_id == OP_SLT) ||
                             ((opcode_id >= OP_MUL) && (opcode_id <= OP_ROR)) ||
                             (opcode_id == OP_STR);
    // JAL doesn't read rs1 (it only writes rd + uses the imm8 field), so it's
    // excluded here just like JMP/RETI/HALT. JR *does* read rs1 (its jump
    // target register) so it deliberately stays out of this exclusion list.
    wire id_uses_rs1 = !(opcode_id == OP_LDI || opcode_id == OP_LDD ||
                         opcode_id == OP_JMP || opcode_id == OP_JAL ||
                         opcode_id == OP_RETI || opcode_id == OP_HALT);
`ifdef EXCEPTION_V2
    // TRAP/ERET/MFC0 have no general-purpose rs1 input.
    wire id_uses_rs1_v2 = id_uses_rs1 && (opcode_id != `OP_TRAP) &&
                          (opcode_id != `OP_ERET) && (opcode_id != `OP_MFC0);
`endif
    wire id_uses_rd3 = (opcode_id == OP_MAC);
    wire load_use_hazard = ID_EX_reg_we && (ID_EX_res_src == 2'b01) &&
        (ID_EX_rd_addr != {REG_ADDR_W{1'b0}}) &&
        ((
`ifdef EXCEPTION_V2
          id_uses_rs1_v2
`else
          id_uses_rs1
`endif
          && (ID_EX_rd_addr == read_reg_1_id)) ||
         (id_alu_two_source && (ID_EX_rd_addr == read_reg_2_id)) ||
         (id_uses_rd3 && (ID_EX_rd_addr == rd_addr_id)));

`ifdef EXCEPTION_V2
    wire [ADDR_W-1:0] exception_next_pc = exception_taken ? EXCEPTION_VECTOR : next_pc_if;
`endif
    ProgramCounter #(.ADDR_W(ADDR_W)) u_PC (.clk(clk), .rst(system_rst),
        .halt(ID_EX_halt || load_use_hazard),
`ifdef EXCEPTION_V2
        .next_pc(exception_next_pc),
`else
        .next_pc(next_pc_if),
`endif
        .pc(pc_if));
    InstructionMemory #(.ADDR_W(ADDR_W), .INSTR_W(INSTR_W)) u_IMEM (.pc(pc_if), .instr(instr_if));

    // ---------------- IF stage register ----------------
    always @(posedge clk) begin
        if (system_rst || ex_mispredict || trigger_int
`ifdef EXCEPTION_V2
            || exception_taken
`endif
        ) begin
            IF_ID_instr <= {INSTR_W{1'b0}}; IF_ID_pc <= {ADDR_W{1'b0}};
            IF_ID_pred_taken <= 1'b0; IF_ID_fallback_pc <= {ADDR_W{1'b0}};
        end else if (!load_use_hazard) begin
            IF_ID_instr <= instr_if; IF_ID_pc <= pc_if;
            IF_ID_pred_taken <= predict_taken_if; IF_ID_fallback_pc <= pc_if + 1'b1;
        end
    end

    // ---------------- ID stage register (bubble on load-use hazard) ----------------
    always @(posedge clk) begin
        if (system_rst || ex_mispredict || trigger_int || load_use_hazard
`ifdef EXCEPTION_V2
            || exception_taken
`endif
        ) begin
            ID_EX_reg_we <= 1'b0; ID_EX_mem_we <= 1'b0; ID_EX_pc_src <= 1'b0;
            ID_EX_halt <= 1'b0; ID_EX_opcode <= {OPCODE_W{1'b0}}; ID_EX_pred_taken <= 1'b0;
        end else begin
            ID_EX_pc <= IF_ID_pc; ID_EX_rd1 <= reg_rd1_id; ID_EX_rd2 <= reg_rd2_id; ID_EX_rd3 <= reg_rd3_id;
            ID_EX_imm <= imm_id; ID_EX_imm5_sext <= imm5_sext_id; ID_EX_imm5_zext <= imm5_zext_id;
            ID_EX_rd_addr <= rd_addr_id; ID_EX_opcode <= opcode_id;
            ID_EX_rs1_addr <= read_reg_1_id; ID_EX_rs2_addr <= read_reg_2_id; ID_EX_rd_in_addr <= rd_addr_id;
            ID_EX_reg_we <= reg_we_id; ID_EX_mem_we <= mem_we_id; ID_EX_pc_src <= pc_src_id; ID_EX_halt <= halt_id;
            ID_EX_base_reg_src <= base_reg_src_id; ID_EX_mem_addr_src <= mem_addr_src_id;
            ID_EX_alu_b_src <= alu_b_src_id; ID_EX_res_src <= res_src_id;
            ID_EX_pred_taken <= IF_ID_pred_taken; ID_EX_fallback_pc <= IF_ID_fallback_pc;
        end
    end

    // ---------------- EX stage ----------------
    // Forwarding gives EX/MEM priority. Loads are excluded from that path
    // because their value has not reached memory yet.
    wire [DATA_W-1:0] fwd_rd1_ex, fwd_rd2_ex, fwd_rd3_ex;
    ForwardingUnit #(.DATA_W(DATA_W), .REG_ADDR_W(REG_ADDR_W)) u_FWD (
        .EX_MEM_reg_we(EX_MEM_reg_we), .EX_MEM_rd_addr(EX_MEM_rd_addr),
        .EX_MEM_res_src(EX_MEM_res_src), .EX_MEM_alu_result(EX_MEM_alu_result),
        .EX_MEM_imm(EX_MEM_imm),
        .MEM_WB_reg_we(MEM_WB_reg_we), .MEM_WB_rd_addr(MEM_WB_rd_addr),
        .MEM_WB_reg_write_data(MEM_WB_reg_write_data),
        .ID_EX_rs1_addr(ID_EX_rs1_addr), .ID_EX_rs2_addr(ID_EX_rs2_addr),
        .ID_EX_rd_in_addr(ID_EX_rd_in_addr),
        .ID_EX_rd1(ID_EX_rd1), .ID_EX_rd2(ID_EX_rd2), .ID_EX_rd3(ID_EX_rd3),
        .fwd_rd1(fwd_rd1_ex), .fwd_rd2(fwd_rd2_ex), .fwd_rd3(fwd_rd3_ex)
    );
    wire [DATA_W-1:0] alu_b_in_ex = (ID_EX_alu_b_src == 2'b00) ? fwd_rd2_ex :
                          (ID_EX_alu_b_src == 2'b01) ? {DATA_W{1'b0}} : ID_EX_imm5_sext;
    wire [DATA_W-1:0] alu_result_ex; wire zero_ex, greater_ex;
    ALU #(.DATA_W(DATA_W), .OPCODE_W(OPCODE_W)) u_ALU (
        .a(fwd_rd1_ex), .b(alu_b_in_ex), .rd_val(fwd_rd3_ex), .alu_control(ID_EX_opcode),
        .result(alu_result_ex), .zero(zero_ex), .greater(greater_ex));
`ifdef EXCEPTION_V2
    wire [DATA_W:0] add_extended_ex = {1'b0, fwd_rd1_ex} + {1'b0, alu_b_in_ex};
    wire alu_overflow_ex = (ID_EX_reg_we && (ID_EX_opcode == OP_ADD || ID_EX_opcode == OP_ADDI) &&
                            add_extended_ex[DATA_W]);
    wire exception_overflow_ex = alu_overflow_ex && !in_exception && !system_rst;
    // ID faults have priority over fetch but an EX overflow is older, so it
    // wins if both occur in the same cycle.
    wire exception_taken = exception_overflow_ex ||
                           ((!in_exception && !system_rst) && (illegal_instruction_id || trap_id));
    wire [ADDR_W-1:0] exception_fault_pc = exception_overflow_ex ? ID_EX_pc : IF_ID_pc;
    wire [1:0] exception_cause_next = exception_overflow_ex ? CAUSE_OVERFLOW :
                                       illegal_instruction_id ? CAUSE_ILLEGAL : CAUSE_TRAP;
    wire [DATA_W-1:0] alu_result_with_cp0_ex = (ID_EX_opcode == `OP_MFC0) ?
        (ID_EX_imm[0] ? exception_epc : {{(DATA_W-2){1'b0}}, exception_cause}) : alu_result_ex;

    always @(posedge clk) begin
        if (system_rst) begin
            exception_epc <= {ADDR_W{1'b0}};
            exception_cause <= 2'b00;
            in_exception <= 1'b0;
        end else if (exception_taken) begin
            exception_epc <= exception_fault_pc;
            exception_cause <= exception_cause_next;
            in_exception <= 1'b1;
        end else if (eret_taken_ex) begin
            in_exception <= 1'b0;
        end
    end
`endif
    wire [DATA_W-1:0] base_reg_ex = ID_EX_base_reg_src ? fwd_rd2_ex : fwd_rd1_ex;
    wire [DATA_W-1:0] mem_addr_ex = ID_EX_mem_addr_src ? ID_EX_imm : base_reg_ex + ID_EX_imm5_zext;
    // NOTE (Bonus Task 1): fwd_rd1_ex doubles as the JR jump-target register
    // read (rs1_src routes IF_ID_instr[7:5] into read_reg_1 for JR, same as
    // JZ/JNZ/JGT already do), so it's passed into BRU as reg_target below.
    BranchResolutionUnit #(.ADDR_W(ADDR_W), .OPCODE_W(OPCODE_W)) u_BRU (
        .ex_pc(ID_EX_pc), .opcode(ID_EX_opcode), .pc_src(ID_EX_pc_src), .zero(zero_ex), .greater(greater_ex),
        .pred_taken(ID_EX_pred_taken), .imm(ID_EX_imm),
`ifdef EXCEPTION_V2
        .epc(return_epc),
`else
        .epc(epc),
`endif
        .fallback_pc(ID_EX_fallback_pc),
        .reg_target(fwd_rd1_ex),
        .reti_taken(reti_taken_ex), .is_branch_instr(is_branch_instr_ex), .branch_taken(branch_taken_ex),
        .actual_target(actual_target_ex), .ex_mispredict(ex_mispredict), .ex_recovery_pc(ex_recovery_pc)
    );

    // ---------------- EX -> MEM pipeline register ----------------
    always @(posedge clk) begin
        if (system_rst
`ifdef EXCEPTION_V2
            || exception_overflow_ex
`endif
        ) begin EX_MEM_reg_we <= 1'b0; EX_MEM_mem_we <= 1'b0; end
        else begin
            EX_MEM_alu_result <=
`ifdef EXCEPTION_V2
                alu_result_with_cp0_ex;
`else
                alu_result_ex;
`endif
            EX_MEM_mem_addr <= mem_addr_ex; EX_MEM_store_data <= fwd_rd1_ex;
            EX_MEM_imm <= ID_EX_imm; EX_MEM_fallback_pc <= ID_EX_fallback_pc; EX_MEM_rd_addr <= ID_EX_rd_addr;
            EX_MEM_reg_we <= ID_EX_reg_we; EX_MEM_mem_we <= ID_EX_mem_we; EX_MEM_res_src <= ID_EX_res_src;
        end
    end

    // ---------------- MEM stage ----------------
    wire [DATA_W-1:0] mem_rd_mem;
    wire [DATA_W-1:0] motor_duty_cycle_mem;
    DataMemory #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_DMEM (
        .clk(clk), .we(EX_MEM_mem_we), .addr(EX_MEM_mem_addr), .wd(EX_MEM_store_data),
        .digital_in(external_digital_pins), .adc_in(external_adc_pins),
        .rd(mem_rd_mem), .pwm_duty_cycle(motor_duty_cycle_mem));
    always @(posedge clk) begin
        if (system_rst) MEM_WB_reg_we <= 1'b0;
        else begin
            MEM_WB_alu_result <= EX_MEM_alu_result; MEM_WB_mem_data <= mem_rd_mem; MEM_WB_imm <= EX_MEM_imm;
            MEM_WB_fallback_pc <= EX_MEM_fallback_pc;
            MEM_WB_rd_addr <= EX_MEM_rd_addr; MEM_WB_reg_we <= EX_MEM_reg_we; MEM_WB_res_src <= EX_MEM_res_src;
        end
    end

    // ---------------- WB stage ----------------
    // WB is the RegisterFile write port instantiated above in ID.
    PWM_Generator #(.DATA_W(DATA_W)) u_PWM (
        .clk(clk), .rst(system_rst), .duty_cycle(motor_duty_cycle_mem), .pwm_out(motor_pwm_pin));
    ResetSynchronizer u_RstSync (.clk(clk), .async_rst_in(rst), .sync_rst_out(system_rst));
endmodule


// =============================================================================
// SUB-MODULES
// =============================================================================

module BranchResolutionUnit #(
    parameter integer ADDR_W   = 8,
    parameter integer OPCODE_W = 5
) (
    // -- Decode inputs (from ID_EX) --
    input  wire [ADDR_W-1:0]   ex_pc,
    input  wire [OPCODE_W-1:0] opcode,
    input  wire                pc_src,
    input  wire                pred_taken,
    input  wire [7:0]          imm,
    input  wire [ADDR_W-1:0]   fallback_pc,
    input  wire [ADDR_W-1:0]   reg_target,   // NEW: rs1 value, used as JR's jump target

    // -- ALU condition flags (from EX) --
    input  wire                zero,
    input  wire                greater,

    // -- Interrupt-return target --
    input  wire [ADDR_W-1:0]   epc,

    // -- Resolved branch/jump outcome --
    output wire                reti_taken,
    output wire                is_branch_instr,
    output wire                branch_taken,
    output wire [ADDR_W-1:0]   actual_target,
    output wire                ex_mispredict,
    output wire [ADDR_W-1:0]   ex_recovery_pc
);
    localparam [OPCODE_W-1:0] OP_JZ = `OP_JZ, OP_JNZ = `OP_JNZ, OP_JGT = `OP_JGT,
                               OP_JMP = `OP_JMP, OP_JAL = `OP_JAL, OP_JR = `OP_JR,
                               OP_RETI = `OP_RETI;
`ifdef EXCEPTION_V2
    localparam [OPCODE_W-1:0] OP_ERET = `OP_ERET;
`endif

    // Hardware Branch & RETI Evaluation
    assign reti_taken = (opcode == OP_RETI)
`ifdef EXCEPTION_V2
                        || (opcode == OP_ERET)
`endif
                        ;

    assign is_branch_instr = (opcode == OP_JMP) | (opcode == OP_JZ) |
                             (opcode == OP_JNZ) | (opcode == OP_JGT) |
                             (opcode == OP_JAL) | (opcode == OP_JR);

    // JAL and JR are unconditional, always-taken control transfers, same as JMP.
    assign branch_taken = pc_src & (
                        (opcode == OP_JMP) |
                        (opcode == OP_JAL) |
                        (opcode == OP_JR)  |
                        (opcode == OP_JZ  & zero) |
                        (opcode == OP_JNZ & ~zero) |
                        (opcode == OP_JGT & greater));

    // JR's target comes from a register (reg_target); every other taken
    // control-transfer target is PC-relative (ex_pc + imm), same as before.
    // ERET skips the faulting instruction after the handler has repaired its
    // result; EPC itself still holds the exact fault address.
    assign actual_target  = reti_taken ?
`ifdef EXCEPTION_V2
                            ((opcode == OP_ERET) ? (epc + 1'b1) : epc) :
`else
                            epc :
`endif
                             (opcode == OP_JR) ? reg_target : (ex_pc + imm);
    // Force a flush on JR because its target is dynamic and cannot be safely predicted by a standard BTB
    assign ex_mispredict  = (is_branch_instr && (pred_taken != branch_taken)) | reti_taken | (opcode == OP_JR);
    assign ex_recovery_pc = reti_taken ? actual_target : (branch_taken ? actual_target : fallback_pc);

endmodule


// Combines forwarding from the EX/MEM stage (priority) and the MEM/WB stage
// so that no combinational forwarding logic needs to live in the top module.
// EX/MEM forwarding is skipped for loads (res_src == 2'b01) because a load's
// data has not returned from memory yet at that point in the pipeline.
module ForwardingUnit #(
    parameter integer DATA_W     = 8,
    parameter integer REG_ADDR_W = 3
) (
    // -- EX/MEM stage --
    input  wire                    EX_MEM_reg_we,
    input  wire [REG_ADDR_W-1:0]   EX_MEM_rd_addr,
    input  wire [1:0]              EX_MEM_res_src,
    input  wire [DATA_W-1:0]       EX_MEM_alu_result,
    input  wire [DATA_W-1:0]       EX_MEM_imm,

    // -- MEM/WB stage --
    input  wire                    MEM_WB_reg_we,
    input  wire [REG_ADDR_W-1:0]   MEM_WB_rd_addr,
    input  wire [DATA_W-1:0]       MEM_WB_reg_write_data,

    // -- Consumers in ID/EX --
    input  wire [REG_ADDR_W-1:0]   ID_EX_rs1_addr,
    input  wire [REG_ADDR_W-1:0]   ID_EX_rs2_addr,
    input  wire [REG_ADDR_W-1:0]   ID_EX_rd_in_addr,
    input  wire [DATA_W-1:0]       ID_EX_rd1,
    input  wire [DATA_W-1:0]       ID_EX_rd2,
    input  wire [DATA_W-1:0]       ID_EX_rd3,

    // -- Forwarded operands --
    output wire [DATA_W-1:0]       fwd_rd1,
    output wire [DATA_W-1:0]       fwd_rd2,
    output wire [DATA_W-1:0]       fwd_rd3
);

    wire exmem_can_forward = EX_MEM_reg_we && (EX_MEM_rd_addr != {REG_ADDR_W{1'b0}}) && (EX_MEM_res_src != 2'b01);
    wire memwb_can_forward = MEM_WB_reg_we && (MEM_WB_rd_addr != {REG_ADDR_W{1'b0}});
    wire [DATA_W-1:0] EX_MEM_forward_data = (EX_MEM_res_src == 2'b10) ? EX_MEM_imm : EX_MEM_alu_result;

    assign fwd_rd1 = (exmem_can_forward && EX_MEM_rd_addr == ID_EX_rs1_addr) ? EX_MEM_forward_data :
                      (memwb_can_forward && MEM_WB_rd_addr == ID_EX_rs1_addr) ? MEM_WB_reg_write_data : ID_EX_rd1;
    assign fwd_rd2 = (exmem_can_forward && EX_MEM_rd_addr == ID_EX_rs2_addr) ? EX_MEM_forward_data :
                      (memwb_can_forward && MEM_WB_rd_addr == ID_EX_rs2_addr) ? MEM_WB_reg_write_data : ID_EX_rd2;
    assign fwd_rd3 = (exmem_can_forward && EX_MEM_rd_addr == ID_EX_rd_in_addr) ? EX_MEM_forward_data :
                      (memwb_can_forward && MEM_WB_rd_addr == ID_EX_rd_in_addr) ? MEM_WB_reg_write_data : ID_EX_rd3;

endmodule


module BranchPredictor #(
    parameter integer ADDR_W = 8
) (
    // -- Clock / Reset --
    input  wire               clk,
    input  wire               rst,

    // -- IF stage lookup --
    input  wire [ADDR_W-1:0]  pc,
    input  wire [ADDR_W-1:0]  pc_plus_1,
    input  wire               trigger_int,
    output wire [ADDR_W-1:0]  next_pc,
    output wire               predict_taken,

    // -- EX stage update (resolved branch outcome) --
    input  wire               ex_is_branch,
    input  wire [ADDR_W-1:0]  ex_pc,
    input  wire [ADDR_W-1:0]  ex_actual_target,
    input  wire               ex_branch_taken,
    input  wire               ex_mispredict,
    input  wire [ADDR_W-1:0]  ex_recovery_pc
);
    reg valid_btb [0:31];                   
    reg [ADDR_W-1:0] btb_tag [0:31];    // stores pc value
    reg [ADDR_W-1:0] btb_target [0:31]; // stores corresponding target address
    reg bht [0:31];                     // 1-bit Branch History Table (BHT) for taken/not-taken prediction

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            valid_btb[i] = 0;
            bht[i] = 0;
        end
    end

    wire [4:0] if_idx = pc[4:0];      // index for BTB and BHT arrays using lower 5 bits of the PC
    wire if_hit = valid_btb[if_idx] && (btb_tag[if_idx] == pc);  // pc is in the BTB and valid

    assign predict_taken = if_hit && bht[if_idx];  // pc exists and was taken last time -> predict taken
    wire [ADDR_W-1:0] predicted_target = predict_taken ? btb_target[if_idx] : pc_plus_1;

    wire [ADDR_W-1:0] resolved_next_pc = (ex_mispredict) ? ex_recovery_pc : predicted_target;
    assign next_pc = trigger_int ? 8'h80 : resolved_next_pc; 

    wire [4:0] ex_idx = ex_pc[4:0];
    always @(posedge clk) begin
        if (!rst && ex_is_branch) begin
            valid_btb[ex_idx]   <= 1;
            btb_tag[ex_idx]     <= ex_pc;
            btb_target[ex_idx]  <= ex_actual_target;
            bht[ex_idx]         <= ex_branch_taken;
        end
    end
endmodule

module InterruptController #(
    parameter integer ADDR_W = 8
) (
    // -- Clock / Reset --
    input  wire               clk,
    input  wire               rst,

    // -- External interrupt request --
    input  wire               interrupt_pin,

    // -- ISR exit / mispredict recovery --
    input  wire               reti_taken,
    input  wire               ex_mispredict,
    input  wire [ADDR_W-1:0]  ex_recovery_pc,
    input  wire [ADDR_W-1:0]  IF_ID_pc,

    // -- ISR entry --
    output wire                trigger_int,
    output reg  [ADDR_W-1:0]   epc
);
    reg int_d;   // used to detect rising edge of interrupt_pin
    reg in_isr;  // flag indicating whether we are currently inside an ISR

    always @(posedge clk) begin
        if (rst) int_d <= 1'b0;
        else     int_d <= interrupt_pin;
    end
    
    wire int_edge = interrupt_pin & ~int_d; // rising edge of interrupt_pin
    assign trigger_int = int_edge & ~in_isr & ~rst; // only trigger if not already in ISR / reset

    always @(posedge clk) begin
        if (rst) begin
            in_isr <= 1'b0;
            epc    <= {ADDR_W{1'b0}};
        end else if (trigger_int) begin
            in_isr <= 1'b1;
            epc    <= (ex_mispredict) ? ex_recovery_pc : IF_ID_pc; 
        end else if (reti_taken) begin
            in_isr <= 1'b0;
        end
    end
endmodule

module ProgramCounter #(
    parameter integer ADDR_W = 8
) (
    input  wire                clk,
    input  wire                rst,
    input  wire                halt,
    input  wire [ADDR_W-1:0]   next_pc,
    output reg  [ADDR_W-1:0]   pc
);
    always @(posedge clk) begin
        if (rst)       pc <= {ADDR_W{1'b0}};
        else if (halt) pc <= pc;
        else           pc <= next_pc;
    end
endmodule

module InstructionMemory #(
    parameter integer ADDR_W  = 8,
    parameter integer INSTR_W = 16
) (
    input  wire [ADDR_W-1:0]   pc,
    output wire [INSTR_W-1:0]  instr
);
    reg [INSTR_W-1:0] memory [0:(1<<ADDR_W)-1];
    assign instr = memory[pc];
endmodule

module RegisterFile #(
    parameter integer DATA_W     = 8,
    parameter integer REG_ADDR_W = 3
) (
    // -- Clock --
    input  wire                    clk,

    // -- Write port (WB stage) --
    input  wire                    we,
    input  wire [REG_ADDR_W-1:0]   wa,
    input  wire [DATA_W-1:0]       wd,

    // -- Read ports (ID stage) --
    input  wire [REG_ADDR_W-1:0]   rs1,
    input  wire [REG_ADDR_W-1:0]   rs2,
    input  wire [REG_ADDR_W-1:0]   rs3,
    output wire [DATA_W-1:0]       rd1,
    output wire [DATA_W-1:0]       rd2,
    output wire [DATA_W-1:0]       rd3
);
    reg [DATA_W-1:0] registers [0:(1<<REG_ADDR_W)-1];
    integer i;
    initial begin
        for (i = 0; i < (1<<REG_ADDR_W); i = i + 1) begin
            registers[i] = {DATA_W{1'b0}};
        end
    end

    // r0 is hardwired to zero; same-cycle write-through for the other regs.
    assign rd1 = (rs1 == {REG_ADDR_W{1'b0}}) ? {DATA_W{1'b0}} : (we && (wa == rs1)) ? wd : registers[rs1];
    assign rd2 = (rs2 == {REG_ADDR_W{1'b0}}) ? {DATA_W{1'b0}} : (we && (wa == rs2)) ? wd : registers[rs2];
    assign rd3 = (rs3 == {REG_ADDR_W{1'b0}}) ? {DATA_W{1'b0}} : (we && (wa == rs3)) ? wd : registers[rs3];

    always @(posedge clk) begin
        if (we && (wa != {REG_ADDR_W{1'b0}})) registers[wa] <= wd;
    end
endmodule


module ALU #(
    parameter integer DATA_W   = 8,
    parameter integer OPCODE_W = 5
) (
    input  wire [DATA_W-1:0]   a,
    input  wire [DATA_W-1:0]   b,
    input  wire [DATA_W-1:0]   rd_val,
    input  wire [OPCODE_W-1:0] alu_control,
    output reg  [DATA_W-1:0]   result,
    output wire                zero,
    output wire                greater
);
    localparam [OPCODE_W-1:0]
        OP_ADD = `OP_ADD, OP_SUB = `OP_SUB, OP_AND = `OP_AND, OP_OR  = `OP_OR,
        OP_XOR = `OP_XOR, OP_SHL = `OP_SHL, OP_SHR = `OP_SHR, OP_ADDI= `OP_ADDI,
        OP_SLT = `OP_SLT, OP_MUL = `OP_MUL, OP_MAC = `OP_MAC, OP_ROL = `OP_ROL,
        OP_ROR = `OP_ROR;

    wire [2*DATA_W-1:0] mul_prod = a * b;

    always @(*) begin
        case (alu_control)
            OP_ADD,
            OP_ADDI: result = a + b;
            OP_SUB:  result = a - b;
            OP_AND:  result = a & b;
            OP_OR:   result = a | b;
            OP_XOR:  result = a ^ b;
            OP_SHL:  result = a << b[2:0];
            OP_SHR:  result = a >> b[2:0];
            OP_SLT:  result = ($signed(a) < $signed(b)) ? {{(DATA_W-1){1'b0}}, 1'b1} : {DATA_W{1'b0}};
            OP_MUL:  result = mul_prod[DATA_W-1:0];
            OP_MAC:  result = rd_val + mul_prod[DATA_W-1:0];
            OP_ROL:  result = (a << b[2:0]) | (a >> (DATA_W - b[2:0]));
            OP_ROR:  result = (a >> b[2:0]) | (a << (DATA_W - b[2:0]));
            default: result = {DATA_W{1'b0}};
        endcase
    end

    assign zero    = (a == b);
    assign greater = ($signed(a) > $signed(b));
endmodule

module DataMemory #(
    parameter integer DATA_W = 8,
    parameter integer ADDR_W = 8
) (
    // -- Clock --
    input  wire                  clk,

    // -- CPU memory port --
    input  wire                  we,
    input  wire [ADDR_W-1:0]     addr,
    input  wire [DATA_W-1:0]     wd,
    output wire [DATA_W-1:0]     rd,

    // -- Memory-mapped peripheral I/O --
    input  wire [DATA_W-1:0]     digital_in,
    input  wire [DATA_W-1:0]     adc_in,
    output reg  [DATA_W-1:0]     pwm_duty_cycle
);
    reg [DATA_W-1:0] memory [0:(1<<ADDR_W)-1];
    initial begin
        pwm_duty_cycle = {DATA_W{1'b0}};
    end

    assign rd = (addr == 8'hFF) ? pwm_duty_cycle : 
                (addr == 8'hFE) ? digital_in : 
                (addr == 8'hFD) ? adc_in : 
                memory[addr];

    always @(posedge clk) begin
        if (we) begin
            if (addr == 8'hFF) pwm_duty_cycle <= wd;
            else if (addr != 8'hFE && addr != 8'hFD) memory[addr] <= wd; 
        end
    end
endmodule

module ControlUnit #(
    parameter integer OPCODE_W = 5
) (
    input  wire [OPCODE_W-1:0] opcode,
    input  wire                zero,
    input  wire                greater,
    output reg                 reg_we,
    output reg                 mem_we,
    output reg  [1:0]          alu_b_src,
    output reg  [1:0]          res_src,
    output reg                 pc_src,
    output reg                 rs1_src,
    output reg                 rs2_src,
    output reg                 mem_addr_src,
    output reg                 base_reg_src,
    output reg                 halt
);
    localparam [OPCODE_W-1:0]
        OP_ADD=`OP_ADD, OP_SUB=`OP_SUB, OP_AND=`OP_AND, OP_OR=`OP_OR, OP_XOR=`OP_XOR,
        OP_SHL=`OP_SHL, OP_SHR=`OP_SHR, OP_SLT=`OP_SLT,
        OP_MUL=`OP_MUL, OP_MAC=`OP_MAC, OP_ROL=`OP_ROL, OP_ROR=`OP_ROR,
        OP_LDI=`OP_LDI, OP_ADDI=`OP_ADDI, OP_LDD=`OP_LDD, OP_STR=`OP_STR, OP_STD=`OP_STD,
        OP_JMP=`OP_JMP, OP_JZ=`OP_JZ, OP_JNZ=`OP_JNZ, OP_JGT=`OP_JGT,
        OP_JAL=`OP_JAL, OP_JR=`OP_JR,
        OP_RETI=`OP_RETI, OP_HALT=`OP_HALT;
`ifdef EXCEPTION_V2
    localparam [OPCODE_W-1:0] OP_TRAP=`OP_TRAP, OP_ERET=`OP_ERET, OP_MFC0=`OP_MFC0;
`endif

    always @(*) begin
        reg_we       = 0; mem_we       = 0; pc_src       = 0;
        halt         = 0; alu_b_src    = 2'b00; res_src      = 2'b00;
        mem_addr_src = 0; base_reg_src = 0; rs1_src      = 0; rs2_src      = 0;

        case(opcode)
            OP_ADD, OP_SUB, OP_AND, OP_OR,
            OP_XOR, OP_SHL, OP_SHR, OP_SLT: begin // ALU Base
                reg_we = 1;
            end
            OP_MUL, OP_MAC, OP_ROL, OP_ROR: begin // ALU Advanced
                reg_we = 1;
            end
            OP_LDI: begin // Load immediate
                reg_we  = 1; res_src = 2'b10;
            end
            OP_ADDI: begin // Add immediate
                reg_we    = 1; alu_b_src = 2'b10;
            end
            OP_LDD: begin // Load, base register + displacement
                reg_we       = 1; res_src      = 2'b01;
                base_reg_src = 0; mem_addr_src = 0;
            end
            OP_STR: begin // Store, base register + displacement
                mem_we       = 1; rs1_src      = 1; rs2_src      = 1;
                base_reg_src = 1; mem_addr_src = 0;
            end
            OP_STD: begin // Store direct: mem[imm8] = rs
                mem_we       = 1; // enable memory write
                rs1_src      = 1; // read the source register (bits 10:8)
                mem_addr_src = 1; // route the 8-bit immediate directly to the address
            end
            OP_JMP: begin
                pc_src = 1;
            end
            OP_JZ: begin
                alu_b_src = 2'b01; pc_src    = 1; rs1_src   = 1;
            end
            OP_JNZ: begin
                alu_b_src = 2'b01; pc_src    = 1; rs1_src   = 1;
            end
            OP_JGT: begin
                alu_b_src = 2'b01; pc_src    = 1; rs1_src   = 1;
            end
            OP_JAL: begin // NEW: rd <- PC+1 (link), unconditional PC-relative jump
                reg_we  = 1; pc_src  = 1; res_src = 2'b11;
            end
            OP_JR: begin // NEW: PC <- reg[rs1], unconditional, no link written
                pc_src  = 1; rs1_src = 1;
            end
            OP_RETI: begin
                // no datapath control needed; handled by InterruptController
            end
`ifdef EXCEPTION_V2
            OP_TRAP, OP_ERET: begin
                // The Exception Control Unit / BranchResolutionUnit handles these.
            end
            OP_MFC0: begin
                // CP0 read value is selected in EX from imm[0].
                reg_we = 1;
            end
`endif
            OP_HALT: begin
                halt = 1;
            end
            default: ;
        endcase
    end
endmodule

module Extender #(
    parameter integer DATA_W = 8,
    parameter integer IMM5_W = 5
) (
    input  wire [IMM5_W-1:0] imm5,
    output wire [DATA_W-1:0] imm5_sext,
    output wire [DATA_W-1:0] imm5_zext
);
    assign imm5_sext = {{(DATA_W-IMM5_W){imm5[IMM5_W-1]}}, imm5};
    assign imm5_zext = {{(DATA_W-IMM5_W){1'b0}}, imm5};
endmodule

module PWM_Generator #(
    parameter integer DATA_W = 8
) (
    input  wire               clk,
    input  wire               rst,
    input  wire [DATA_W-1:0]  duty_cycle,
    output reg                pwm_out
);
    reg [DATA_W-1:0] counter;
    always @(posedge clk) begin
        if (rst) begin
            counter <= {DATA_W{1'b0}}; pwm_out <= 1'b0;
        end else begin
            counter <= counter + 1'b1;
            pwm_out <= (counter < duty_cycle) ? 1'b1 : 1'b0;
        end
    end
endmodule

module ResetSynchronizer (
    input  wire clk,
    input  wire async_rst_in,
    output reg  sync_rst_out
);
    reg rst_ff1;
    always @(posedge clk or posedge async_rst_in) begin
        if (async_rst_in) begin
            rst_ff1      <= 1'b1; sync_rst_out <= 1'b1;
        end else begin
            rst_ff1      <= 1'b0; sync_rst_out <= rst_ff1;
        end
    end
endmodule
`default_nettype wire
