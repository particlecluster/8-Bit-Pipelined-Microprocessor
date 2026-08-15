`timescale 1ns / 1ps
`default_nettype none

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

module CPU_Core_5Stage #(
    parameter integer DATA_W     = 8,
    parameter integer ADDR_W     = 8,
    parameter integer INSTR_W    = 16,
    parameter integer OPCODE_W   = 5,
    parameter integer REG_ADDR_W = 3,
    parameter integer IMM5_W     = 5,
    parameter integer CLK_FREQ_HZ = 25_000_000,   // UPDATED: Must match your new 25 MHz clock!
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire              clk_100mhz,          // 100 MHz onboard clock
    input  wire              rst,                 // Reset button
    output wire [3:0]        led_out,             // LD3..LD0 onboard green LEDs
    inout  wire              i2c_sda,             // MPU-6050 I2C SDA
    inout  wire              i2c_scl,             // MPU-6050 I2C SCL
    output wire [7:0]        matrix_rows,         // PMOD JC (Row 0..7, Anodes)
    output wire [7:0]        matrix_cols          // PMOD JD (Col 0..7, Cathodes)
);

    // Unused ports tied off
    wire              interrupt_pin = 1'b0;
    wire [DATA_W-1:0] external_digital_pins = 8'b0;
    wire [DATA_W-1:0] external_adc_pins = 8'b0;
    wire              motor_pwm_pin;
    wire              uart_rx = 1'b1;
    wire              uart_tx;

    // --- NEW CLOCKING LOGIC ---
    wire clk; // This is the new, safe 25MHz clock that runs your CPU

    clk_wiz_0 u_clock_divider (
        .clk_in1(clk_100mhz),
        .clk_out1(clk)
    );
    // --------------------------

    wire system_rst;
    
    reg [INSTR_W-1:0] IF_ID_instr;
    reg [ADDR_W-1:0]  IF_ID_pc;
    reg               IF_ID_pred_taken;
    reg [ADDR_W-1:0]  IF_ID_fallback_pc;

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

    reg [DATA_W-1:0]     EX_MEM_alu_result, EX_MEM_mem_addr, EX_MEM_store_data, EX_MEM_imm;
    reg [ADDR_W-1:0]     EX_MEM_fallback_pc; 
    reg [REG_ADDR_W-1:0] EX_MEM_rd_addr;
    reg                  EX_MEM_reg_we, EX_MEM_mem_we;
    reg [1:0]            EX_MEM_res_src;

    reg [DATA_W-1:0]     MEM_WB_alu_result, MEM_WB_mem_data, MEM_WB_imm;
    reg [ADDR_W-1:0]     MEM_WB_fallback_pc; 
    reg [REG_ADDR_W-1:0] MEM_WB_rd_addr;
    reg                  MEM_WB_reg_we;
    reg [1:0]            MEM_WB_res_src;

    wire [DATA_W-1:0] MEM_WB_reg_write_data =
        (MEM_WB_res_src == 2'b00) ? MEM_WB_alu_result :
        (MEM_WB_res_src == 2'b01) ? MEM_WB_mem_data   :
        (MEM_WB_res_src == 2'b10) ? MEM_WB_imm        : MEM_WB_fallback_pc;

    ResetSynchronizer u_RstSync (
        .clk(clk), 
        .async_rst_in(!rst), 
        .sync_rst_out(system_rst)
    );

    wire [ADDR_W-1:0]  pc_if, next_pc_if;
    wire [INSTR_W-1:0] instr_if;
    wire               predict_taken_if, trigger_int;
    wire [ADDR_W-1:0]  epc;
    
    wire reti_taken_ex = (ID_EX_opcode == `OP_RETI);
    wire eret_taken_ex = (ID_EX_opcode == `OP_ERET) && in_exception;
    wire return_taken_ex = reti_taken_ex || eret_taken_ex;
    wire reti_taken_bru, is_branch_instr_ex, branch_taken_ex, ex_mispredict;
    wire [ADDR_W-1:0] actual_target_ex, ex_recovery_pc;

    wire              exception_taken;
    wire [ADDR_W-1:0] exception_vector_pc;
    wire [ADDR_W-1:0] exception_epc;
    wire [1:0]        exception_cause;
    wire              in_exception;
    
    wire [ADDR_W-1:0] return_pc_ex = eret_taken_ex ? (exception_epc + 1'b1) : epc;

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
        end else if (!load_use_hazard && !ID_EX_halt) begin
            IF_ID_instr       <= instr_if; 
            IF_ID_pc          <= pc_if;
            IF_ID_pred_taken  <= predict_taken_if; 
            IF_ID_fallback_pc <= pc_if + 1'b1;
        end
    end

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
        end else if (ID_EX_halt) begin
            ID_EX_reg_we <= 1'b0;
            ID_EX_mem_we <= 1'b0;
            ID_EX_pc_src <= 1'b0;
            ID_EX_halt   <= 1'b1;
            ID_EX_opcode <= `OP_HALT;
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

    wire [DATA_W-1:0] fwd_rd1_ex, fwd_rd2_ex, fwd_rd3_ex;
    
    ForwardingUnit #(.DATA_W(DATA_W), .REG_ADDR_W(REG_ADDR_W)) u_FWD (
        .EX_MEM_reg_we(EX_MEM_reg_we),           .EX_MEM_rd_addr(EX_MEM_rd_addr),
        .EX_MEM_res_src(EX_MEM_res_src),         .EX_MEM_alu_result(EX_MEM_alu_result),
        .EX_MEM_imm(EX_MEM_imm),                 .EX_MEM_fallback_pc(EX_MEM_fallback_pc),
        .MEM_WB_reg_we(MEM_WB_reg_we), 
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

    wire sign_a = fwd_rd1_ex[DATA_W-1];
    wire sign_b = alu_b_in_ex[DATA_W-1];
    wire sign_res = alu_result_ex[DATA_W-1];
    
    wire signed_overflow = (sign_a == sign_b) && (sign_a != sign_res);
    wire [DATA_W:0] add_extended_ex = {1'b0, fwd_rd1_ex} + {1'b0, alu_b_in_ex};
    wire alu_overflow_ex = ID_EX_reg_we &&
        (((ID_EX_opcode == `OP_ADD)  && (add_extended_ex[DATA_W] || signed_overflow)) ||
         ((ID_EX_opcode == `OP_ADDI) && signed_overflow));

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
        .reg_target(fwd_rd1_ex),           .return_taken(return_taken_ex),
        .return_pc(return_pc_ex),          .reti_taken(reti_taken_bru),
        .is_branch_instr(is_branch_instr_ex), .branch_taken(branch_taken_ex),
        .actual_target(actual_target_ex),  
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
    
    wire i2c_write_cmd  = EX_MEM_mem_we && (EX_MEM_mem_addr == 8'hF7);
    wire i2c_write_data = EX_MEM_mem_we && (EX_MEM_mem_addr == 8'hF8);
    wire [7:0] i2c_data_out_mem;
    wire [2:0] i2c_status_out_mem;
    wire       i2c_scl_oe;
    wire       i2c_sda_oe;
    wire       i2c_scl_in;
    wire       i2c_sda_in;

    I2C_Peripheral #(
        .SYS_CLK_FREQ(25_000_000),
        .I2C_CLK_FREQ(100_000)
    ) u_I2C (
        .clk(clk),
        .rst(system_rst),
        .cmd_write(i2c_write_cmd),
        .data_write(i2c_write_data),
        .cmd_reg(EX_MEM_store_data[4:0]),
        .data_in(EX_MEM_store_data),
        .data_out(i2c_data_out_mem),
        .status_reg(i2c_status_out_mem),
        .scl_in(i2c_scl_in),
        .scl_oe(i2c_scl_oe),
        .sda_in(i2c_sda_in),
        .sda_oe(i2c_sda_oe)
    );

    // Bidirectional I2C buffers (Tristates)
    assign i2c_scl = i2c_scl_oe ? 1'b0 : 1'bz;
    assign i2c_scl_in = i2c_scl;

    assign i2c_sda = i2c_sda_oe ? 1'b0 : 1'bz;
    assign i2c_sda_in = i2c_sda;

    wire [DATA_W-1:0] accel_x_mem;
    wire [DATA_W-1:0] accel_y_mem;

    // -----------------------------------------------------------------------
    // Hardware tilt-to-LED mapping with deadzone threshold to eliminate flicker
    //  accel_x and accel_y are signed 8-bit two's-complement values from MPU-6050
    //
    //  Tilt FORWARD  (acc_x negative, < -TILT_THRESH) => LD3 ON (led_out[3], Pin T10 / LD7)
    //  Tilt BACK     (acc_x positive, >  TILT_THRESH) => LD2 ON (led_out[2], Pin T9  / LD6)
    //  Tilt RIGHT    (acc_y positive, >  TILT_THRESH) => LD1 ON (led_out[1], Pin J5  / LD5)
    //  Tilt LEFT     (acc_y negative, < -TILT_THRESH) => LD0 ON (led_out[0], Pin H5  / LD4)
    // -----------------------------------------------------------------------
    localparam signed [7:0] TILT_THRESH = 8'sd8;

    wire signed [7:0] s_accel_x = accel_x_mem;
    wire signed [7:0] s_accel_y = accel_y_mem;

    assign led_out[3] = (s_accel_x < -TILT_THRESH); // LD3: Tilt Forward
    assign led_out[2] = (s_accel_x >  TILT_THRESH); // LD2: Tilt Backward
    assign led_out[1] = (s_accel_y >  TILT_THRESH); // LD1: Tilt Right
    assign led_out[0] = (s_accel_y < -TILT_THRESH); // LD0: Tilt Left

    // -----------------------------------------------------------------------
    // 8x8 LED Matrix Controller (2x2 dot centered at rest, moves with tilt)
    // -----------------------------------------------------------------------
    LED_Matrix_Controller u_LED_Matrix (
        .clk(clk),
        .rst(system_rst),
        .accel_x(accel_x_mem),
        .accel_y(accel_y_mem),
        .matrix_rows(matrix_rows),
        .matrix_cols(matrix_cols)
    );

    DataMemory_UART #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_DMEM (
        .clk(clk),                               .we(EX_MEM_mem_we), 
        .addr(EX_MEM_mem_addr),                  .wd(EX_MEM_store_data),
        .digital_in(external_digital_pins),      .adc_in(external_adc_pins),
        .uart_rx_data(uart_rx_data_mem),         .uart_status(uart_status_mem),
        .rd(mem_rd_mem),                         .pwm_duty_cycle(motor_duty_cycle_mem),
        .i2c_data_in(i2c_data_out_mem),
        .i2c_status_in({{(DATA_W-3){1'b0}}, i2c_status_out_mem}),
        .accel_x(accel_x_mem),
        .accel_y(accel_y_mem)
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

    PWM_Generator #(.DATA_W(DATA_W)) u_PWM (
        .clk(clk), 
        .rst(system_rst), 
        .duty_cycle(motor_duty_cycle_mem), 
        .pwm_out(motor_pwm_pin)
    );

endmodule

module Exception_Unit #(
    parameter integer ADDR_W = 8,
    parameter integer DATA_W = 8
)(
    input  wire clk,
    input  wire rst,
    input  wire id_illegal_inst,
    input  wire id_trap,
    input  wire ex_overflow,
    input  wire eret_taken,
    input  wire [ADDR_W-1:0] if_pc,
    input  wire [ADDR_W-1:0] ex_pc,
    
    output wire              exception_taken,
    output wire [ADDR_W-1:0] exception_vector_pc,
    output reg  [ADDR_W-1:0] exception_epc,
    output reg  [1:0]        exception_cause,
    output reg               in_exception
);

    localparam [ADDR_W-1:0] EXCEPTION_VECTOR = 8'h80;
    localparam [1:0] CAUSE_OVERFLOW = 2'd1, CAUSE_ILLEGAL = 2'd2, CAUSE_TRAP = 2'd3;

    assign exception_taken = ex_overflow || ((!in_exception && !rst) && (id_illegal_inst || id_trap));
    assign exception_vector_pc = EXCEPTION_VECTOR;
    
    wire [ADDR_W-1:0] exception_fault_pc = ex_overflow ? ex_pc : if_pc;
    wire [1:0] exception_cause_next = ex_overflow ? CAUSE_OVERFLOW : id_illegal_inst ? CAUSE_ILLEGAL : CAUSE_TRAP;

    always @(posedge clk) begin
        if (rst) begin
            exception_epc   <= {ADDR_W{1'b0}};
            exception_cause <= 2'b00;
            in_exception    <= 1'b0;
        end else if (exception_taken) begin
            exception_epc   <= exception_fault_pc;
            exception_cause <= exception_cause_next;
            in_exception    <= 1'b1;
        end else if (eret_taken) begin
            in_exception    <= 1'b0;
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
    always @(*) begin
        reg_we       = 0;  mem_we       = 0;  pc_src       = 0;
        halt         = 0;  alu_b_src    = 2'b00; res_src   = 2'b00;
        mem_addr_src = 0;  base_reg_src = 0;  rs1_src      = 0;  rs2_src = 0;

        case(opcode)
            `OP_ADD, `OP_SUB, `OP_AND, `OP_OR, `OP_XOR, `OP_SHL, `OP_SHR, `OP_SLT,
            `OP_MUL, `OP_MAC, `OP_ROL, `OP_ROR: begin
                reg_we = 1;
            end
            `OP_LDI: begin 
                reg_we = 1;  res_src = 2'b10;
            end
            `OP_ADDI: begin 
                reg_we = 1;  alu_b_src = 2'b10;
            end
            `OP_LDD: begin 
                reg_we = 1;  res_src = 2'b01; base_reg_src = 0; mem_addr_src = 0;
            end
            `OP_STR: begin 
                mem_we = 1;  rs1_src = 1;     rs2_src = 1;      base_reg_src = 1; mem_addr_src = 0;
            end
            `OP_STD: begin 
                mem_we = 1;  rs1_src = 1;     mem_addr_src = 1;
            end
            `OP_JMP: begin
                pc_src = 1;
            end
            `OP_JZ, `OP_JNZ, `OP_JGT: begin
                alu_b_src = 2'b01; pc_src = 1; rs1_src = 1;
            end
            `OP_JAL: begin 
                reg_we = 1;  pc_src = 1; res_src = 2'b11; 
            end
            `OP_JR: begin 
                pc_src = 1;  rs1_src = 1; 
            end
            `OP_TRAP, `OP_ERET: begin
            end
            `OP_MFC0: begin
                reg_we = 1;
            end
            `OP_HALT: begin
                halt = 1;
            end
            default: ;
        endcase
    end
endmodule

module BranchResolutionUnit #(
    parameter integer ADDR_W   = 8,
    parameter integer OPCODE_W = 5
) (
    input  wire [ADDR_W-1:0]   ex_pc,
    input  wire [OPCODE_W-1:0] opcode,
    input  wire                pc_src,
    input  wire                pred_taken,
    input  wire [7:0]          imm,
    input  wire [ADDR_W-1:0]   fallback_pc,
    input  wire [ADDR_W-1:0]   reg_target,   
    input  wire                zero,
    input  wire                greater,
    input  wire                return_taken,
    input  wire [ADDR_W-1:0]   return_pc,

    output wire                reti_taken,
    output wire                is_branch_instr,
    output wire                branch_taken,
    output wire [ADDR_W-1:0]   actual_target,
    output wire                ex_mispredict,
    output wire [ADDR_W-1:0]   ex_recovery_pc
);

    assign is_branch_instr = (opcode == `OP_JMP) | (opcode == `OP_JZ) |
                             (opcode == `OP_JNZ) | (opcode == `OP_JGT) |
                             (opcode == `OP_JAL) | (opcode == `OP_JR);
                             
    assign reti_taken = return_taken;

    assign branch_taken = pc_src & (
                          (opcode == `OP_JMP) |
                          (opcode == `OP_JAL) |
                          (opcode == `OP_JR)  |
                          (opcode == `OP_JZ  & zero) |
                          (opcode == `OP_JNZ & ~zero) |
                          (opcode == `OP_JGT & greater));

    assign actual_target  = return_taken ? return_pc :
                            (opcode == `OP_JR) ? reg_target : (ex_pc + imm);

    assign ex_mispredict  = (is_branch_instr && (pred_taken != branch_taken)) | reti_taken | (opcode == `OP_JR);
    assign ex_recovery_pc = reti_taken ? actual_target : (branch_taken ? actual_target : fallback_pc);

endmodule

module ForwardingUnit #(
    parameter integer DATA_W     = 8,
    parameter integer REG_ADDR_W = 3
) (
    input  wire                  EX_MEM_reg_we,
    input  wire [REG_ADDR_W-1:0] EX_MEM_rd_addr,
    input  wire [1:0]            EX_MEM_res_src,
    input  wire [DATA_W-1:0]     EX_MEM_alu_result,
    input  wire [DATA_W-1:0]     EX_MEM_imm,
    input  wire [DATA_W-1:0]     EX_MEM_fallback_pc,
    input  wire                  MEM_WB_reg_we,
    input  wire [REG_ADDR_W-1:0] MEM_WB_rd_addr,
    input  wire [DATA_W-1:0]     MEM_WB_reg_write_data,
    input  wire [REG_ADDR_W-1:0] ID_EX_rs1_addr,
    input  wire [REG_ADDR_W-1:0] ID_EX_rs2_addr,
    input  wire [REG_ADDR_W-1:0] ID_EX_rd_in_addr,
    input  wire [DATA_W-1:0]     ID_EX_rd1,
    input  wire [DATA_W-1:0]     ID_EX_rd2,
    input  wire [DATA_W-1:0]     ID_EX_rd3,

    output wire [DATA_W-1:0]     fwd_rd1,
    output wire [DATA_W-1:0]     fwd_rd2,
    output wire [DATA_W-1:0]     fwd_rd3
);

    wire exmem_can_forward = EX_MEM_reg_we && (EX_MEM_rd_addr != {REG_ADDR_W{1'b0}}) && (EX_MEM_res_src != 2'b01);
    wire memwb_can_forward = MEM_WB_reg_we && (MEM_WB_rd_addr != {REG_ADDR_W{1'b0}});
    
    wire [DATA_W-1:0] EX_MEM_forward_data = (EX_MEM_res_src == 2'b10) ? EX_MEM_imm :
                                             (EX_MEM_res_src == 2'b11) ? EX_MEM_fallback_pc :
                                                                         EX_MEM_alu_result;

    assign fwd_rd1 = (exmem_can_forward && EX_MEM_rd_addr == ID_EX_rs1_addr) ? EX_MEM_forward_data :
                     (memwb_can_forward && MEM_WB_rd_addr == ID_EX_rs1_addr) ? MEM_WB_reg_write_data : ID_EX_rd1;
                     
    assign fwd_rd2 = (exmem_can_forward && EX_MEM_rd_addr == ID_EX_rs2_addr) ? EX_MEM_forward_data :
                     (memwb_can_forward && MEM_WB_rd_addr == ID_EX_rs2_addr) ? MEM_WB_reg_write_data : ID_EX_rd2;
                     
    assign fwd_rd3 = (exmem_can_forward && EX_MEM_rd_addr == ID_EX_rd_in_addr) ? EX_MEM_forward_data :
                     (memwb_can_forward && MEM_WB_rd_addr == ID_EX_rd_in_addr) ? MEM_WB_reg_write_data : ID_EX_rd3;

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
    wire [2*DATA_W-1:0] mul_prod = a * b;

    always @(*) begin
        case (alu_control)
            `OP_ADD, `OP_ADDI: result = a + b;
            `OP_SUB:           result = a - b;
            `OP_AND:           result = a & b;
            `OP_OR:            result = a | b;
            `OP_XOR:           result = a ^ b;
            `OP_SHL:           result = a << b[2:0];
            `OP_SHR:           result = a >> b[2:0];
            `OP_SLT:           result = ($signed(a) < $signed(b)) ? {{(DATA_W-1){1'b0}}, 1'b1} : {DATA_W{1'b0}};
            `OP_MUL:           result = mul_prod[DATA_W-1:0];
            `OP_MAC:           result = rd_val + mul_prod[DATA_W-1:0];
            `OP_ROL:           result = (a << b[2:0]) | (a >> (DATA_W - b[2:0]));
            `OP_ROR:           result = (a >> b[2:0]) | (a << (DATA_W - b[2:0]));
            default:           result = {DATA_W{1'b0}};
        endcase
    end

    assign zero    = (a == b);
    assign greater = ($signed(a) > $signed(b));
endmodule

module BranchPredictor #(
    parameter integer ADDR_W = 8
) (
    input  wire               clk,
    input  wire               rst,
    input  wire [ADDR_W-1:0]  pc,
    input  wire [ADDR_W-1:0]  pc_plus_1,
    input  wire               trigger_int,
    output wire [ADDR_W-1:0]  next_pc,
    output wire               predict_taken,
    input  wire               ex_is_branch,
    input  wire [ADDR_W-1:0]  ex_pc,
    input  wire [ADDR_W-1:0]  ex_actual_target,
    input  wire               ex_branch_taken,
    input  wire               ex_mispredict,
    input  wire [ADDR_W-1:0]  ex_recovery_pc
);
    reg valid_btb [0:31];                   
    reg [ADDR_W-1:0] btb_tag [0:31];    
    reg [ADDR_W-1:0] btb_target [0:31]; 
    reg bht [0:31];                     

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            valid_btb[i] = 0;
            bht[i] = 0;
        end
    end

    wire [4:0] if_idx = pc[4:0];      
    wire if_hit = valid_btb[if_idx] && (btb_tag[if_idx] == pc);  

    assign predict_taken = if_hit && bht[if_idx];  
    wire [ADDR_W-1:0] predicted_target = predict_taken ? btb_target[if_idx] : pc_plus_1;
    wire [ADDR_W-1:0] resolved_next_pc = (ex_mispredict) ? ex_recovery_pc : predicted_target;
    
    assign next_pc = trigger_int ? 8'h80 : resolved_next_pc; 

    wire [4:0] ex_idx = ex_pc[4:0];
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                valid_btb[i] <= 1'b0;
                bht[i]       <= 1'b0;
            end
        end else if (ex_is_branch) begin
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
    input  wire               clk,
    input  wire               rst,
    input  wire               interrupt_pin,
    input  wire               reti_taken,
    input  wire               ex_mispredict,
    input  wire [ADDR_W-1:0]  ex_recovery_pc,
    input  wire [ADDR_W-1:0]  IF_ID_pc,
    output wire               trigger_int,
    output reg  [ADDR_W-1:0]  epc
);
    reg int_d;   
    reg in_isr;  

    always @(posedge clk) begin
        if (rst) int_d <= 1'b0;
        else     int_d <= interrupt_pin;
    end
    
    wire int_edge = interrupt_pin & ~int_d; 
    assign trigger_int = int_edge & ~in_isr & ~rst; 

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
    input  wire               clk,
    input  wire               rst,
    input  wire               halt,
    input  wire [ADDR_W-1:0]  next_pc,
    output reg  [ADDR_W-1:0]  pc
);
    always @(posedge clk) begin
        if (rst)       pc <= {ADDR_W{1'b0}};
        else if (halt) pc <= pc;
        else           pc <= next_pc;
    end
endmodule

module InstructionMemory #(
    parameter ADDR_W = 8,
    parameter INSTR_W = 16
) (
    input wire [ADDR_W-1:0] pc,
    output wire [INSTR_W-1:0] instr
);
    reg [INSTR_W-1:0] memory [0:(1<<ADDR_W)-1];
    integer i;

    initial begin
        for (i = 0; i < (1<<ADDR_W); i = i + 1)
            memory[i] = {INSTR_W{1'b0}};
        $readmemh("program.hex.txt", memory);
    end

    assign instr = memory[pc];
endmodule

module RegisterFile #(
    parameter integer DATA_W     = 8,
    parameter integer REG_ADDR_W = 3
) (
    input  wire                  clk,
    input  wire                  we,
    input  wire [REG_ADDR_W-1:0] wa,
    input  wire [DATA_W-1:0]     wd,
    input  wire [REG_ADDR_W-1:0] rs1,
    input  wire [REG_ADDR_W-1:0] rs2,
    input  wire [REG_ADDR_W-1:0] rs3,
    output wire [DATA_W-1:0]     rd1,
    output wire [DATA_W-1:0]     rd2,
    output wire [DATA_W-1:0]     rd3
);
    reg [DATA_W-1:0] registers [0:(1<<REG_ADDR_W)-1];
    integer i;
    
    initial begin
        for (i = 0; i < (1<<REG_ADDR_W); i = i + 1) begin
            registers[i] = {DATA_W{1'b0}};
        end
    end

    assign rd1 = (rs1 == {REG_ADDR_W{1'b0}}) ? {DATA_W{1'b0}} : (we && (wa == rs1)) ? wd : registers[rs1];
    assign rd2 = (rs2 == {REG_ADDR_W{1'b0}}) ? {DATA_W{1'b0}} : (we && (wa == rs2)) ? wd : registers[rs2];
    assign rd3 = (rs3 == {REG_ADDR_W{1'b0}}) ? {DATA_W{1'b0}} : (we && (wa == rs3)) ? wd : registers[rs3];

    always @(posedge clk) begin
        if (we && (wa != {REG_ADDR_W{1'b0}})) registers[wa] <= wd;
    end
endmodule

module DataMemory_UART #(
    parameter integer DATA_W = 8,
    parameter integer ADDR_W = 8
) (
    input  wire              clk,
    input  wire              we,
    input  wire [ADDR_W-1:0] addr,
    input  wire [DATA_W-1:0] wd,
    output wire [DATA_W-1:0] rd,
    input  wire [DATA_W-1:0] digital_in,
    input  wire [DATA_W-1:0] adc_in,
    input  wire [DATA_W-1:0] uart_rx_data,
    input  wire [DATA_W-1:0] uart_status,
    output reg  [DATA_W-1:0] pwm_duty_cycle,
    input  wire [DATA_W-1:0] i2c_data_in,
    input  wire [DATA_W-1:0] i2c_status_in,
    output reg  [DATA_W-1:0] accel_x,      // Accelerometer X data (signed 8-bit from MPU6050)
    output reg  [DATA_W-1:0] accel_y       // Accelerometer Y data (signed 8-bit from MPU6050)
);
    reg [DATA_W-1:0] memory [0:(1<<ADDR_W)-1];
    integer i;

    initial begin
        pwm_duty_cycle = {DATA_W{1'b0}};
        accel_x = 8'h00;
        accel_y = 8'h00;
        
        for (i = 0; i < (1<<ADDR_W); i = i + 1)
            memory[i] = {DATA_W{1'b0}};
    end

    assign rd = (addr == 8'hFF) ? pwm_duty_cycle : 
                (addr == 8'hFE) ? digital_in : 
                (addr == 8'hFD) ? adc_in :
                (addr == 8'hFA) ? uart_status :
                (addr == 8'hFB) ? uart_rx_data :
                (addr == 8'hF8) ? i2c_data_in :  // NEW
                (addr == 8'hF7) ? i2c_status_in :// NEW
                (addr == 8'hF4) ? accel_x :      // NEW
                (addr == 8'hF3) ? accel_y :      // NEW
                memory[addr];

    always @(posedge clk) begin
        if (we) begin       
            if (addr == 8'hFF) begin
                pwm_duty_cycle <= wd;
                memory[addr] <= wd;
            end
            else if (addr == 8'hF4) begin  // accel_x written by CPU I2C program
                accel_x <= wd;
                memory[addr] <= wd;
            end
            else if (addr == 8'hF3) begin  // accel_y written by CPU I2C program
                accel_y <= wd;
                memory[addr] <= wd;
            end
            else if (addr != 8'hFE && addr != 8'hFD && addr != 8'hFA &&
                     addr != 8'hFB && addr != 8'hFC &&
                     addr != 8'hF8 && addr != 8'hF7 && addr != 8'hF4 &&
                     addr != 8'hF3) memory[addr] <= wd; 
        end
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
    input  wire              clk,
    input  wire              rst,
    input  wire [DATA_W-1:0] duty_cycle,
    output reg               pwm_out
);
    reg [DATA_W-1:0] counter;
    
    always @(posedge clk) begin
        if (rst) begin
            counter <= {DATA_W{1'b0}}; 
            pwm_out <= 1'b0;
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
            rst_ff1      <= 1'b1; 
            sync_rst_out <= 1'b1;
        end else begin
            rst_ff1      <= 1'b0; 
            sync_rst_out <= rst_ff1;
        end
    end
endmodule

module UART_Peripheral #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output wire       tx,
    input  wire       tx_write,
    input  wire [7:0] tx_data,
    input  wire       rx_read,
    output wire [7:0] rx_data,
    output wire [7:0] status
);
    wire tx_ready;
    wire rx_valid;
    wire rx_overrun;

    UART_Transmitter #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)
    ) u_TX (
        .clk(clk), .rst(rst), .write_strobe(tx_write), .data_in(tx_data),
        .tx(tx), .ready(tx_ready)
    );

    UART_Receiver #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)
    ) u_RX (
        .clk(clk), .rst(rst), .rx(rx), .read_strobe(rx_read),
        .data_out(rx_data), .valid(rx_valid), .overrun(rx_overrun)
    );

    assign status = {rx_overrun, 5'b00000, tx_ready, rx_valid};
endmodule

module UART_Transmitter #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer CLOCKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       write_strobe,
    input  wire [7:0] data_in,
    output reg        tx,
    output wire       ready
);
    localparam integer COUNTER_W = (CLOCKS_PER_BIT <= 1) ? 1 : $clog2(CLOCKS_PER_BIT);
    localparam [1:0] TX_IDLE = 2'd0, TX_START = 2'd1, TX_DATA = 2'd2, TX_STOP = 2'd3;

    reg [1:0] state;
    reg [COUNTER_W-1:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] shift_data;
    reg busy;

    assign ready = !busy;

    always @(posedge clk) begin
        if (rst) begin
            state      <= TX_IDLE;
            baud_count <= {COUNTER_W{1'b0}};
            bit_index  <= 3'd0;
            shift_data <= 8'd0;
            busy       <= 1'b0;
            tx         <= 1'b1;
        end else if (!busy) begin
            tx <= 1'b1;
            if (write_strobe) begin
                shift_data <= data_in;
                baud_count <= {COUNTER_W{1'b0}};
                bit_index  <= 3'd0;
                state      <= TX_START;
                busy       <= 1'b1;
                tx         <= 1'b0;
            end
        end else if (baud_count == CLOCKS_PER_BIT - 1) begin
            baud_count <= {COUNTER_W{1'b0}};
            case (state)
                TX_START: begin
                    state <= TX_DATA;
                    tx    <= shift_data[0];
                end
                TX_DATA: begin
                    if (bit_index == 3'd7) begin
                        state <= TX_STOP;
                        tx    <= 1'b1;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        tx        <= shift_data[bit_index + 1'b1];
                    end
                end
                default: begin
                    state <= TX_IDLE;
                    busy  <= 1'b0;
                    tx    <= 1'b1;
                end
            endcase
        end else begin
            baud_count <= baud_count + 1'b1;
        end
    end
endmodule

module UART_Receiver #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer CLOCKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    input  wire       read_strobe,
    output reg  [7:0] data_out,
    output reg        valid,
    output reg        overrun
);
    localparam integer COUNTER_W = (CLOCKS_PER_BIT <= 1) ? 1 : $clog2(CLOCKS_PER_BIT);
    localparam integer HALF_BIT = (CLOCKS_PER_BIT <= 1) ? 1 : CLOCKS_PER_BIT / 2;
    localparam [1:0] RX_IDLE = 2'd0, RX_START = 2'd1, RX_DATA = 2'd2, RX_STOP = 2'd3;

    reg rx_meta, rx_sync;
    reg [1:0] state;
    reg [COUNTER_W-1:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] shift_data;

    always @(posedge clk) begin
        if (rst) begin
            rx_meta    <= 1'b1;
            rx_sync    <= 1'b1;
            state      <= RX_IDLE;
            baud_count <= {COUNTER_W{1'b0}};
            bit_index  <= 3'd0;
            shift_data <= 8'd0;
            data_out   <= 8'd0;
            valid      <= 1'b0;
            overrun    <= 1'b0;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;

            if (read_strobe) valid <= 1'b0;

            case (state)
                RX_IDLE: if (!rx_sync) begin
                    baud_count <= {COUNTER_W{1'b0}};
                    state <= RX_START;
                end
                RX_START: if (baud_count == HALF_BIT - 1) begin
                    baud_count <= {COUNTER_W{1'b0}};
                    if (!rx_sync) begin
                        bit_index <= 3'd0;         
                        baud_count <= HALF_BIT;
                        state <= RX_DATA;
                    end else state <= RX_IDLE;
                end else baud_count <= baud_count + 1'b1;
                RX_DATA: if (baud_count == CLOCKS_PER_BIT - 1) begin
                    baud_count <= {COUNTER_W{1'b0}};
                    shift_data[bit_index] <= rx_sync;
                    if (bit_index == 3'd7) state <= RX_STOP;
                    else bit_index <= bit_index + 1'b1;
                end else baud_count <= baud_count + 1'b1;
                default: if (baud_count == CLOCKS_PER_BIT - 1) begin
                    baud_count <= {COUNTER_W{1'b0}};
                    state <= RX_IDLE;
                    if (rx_sync) begin
                        if (valid) overrun <= 1'b1;
                        else begin
                            data_out <= shift_data;
                            valid <= 1'b1;
                        end
                    end
                end else baud_count <= baud_count + 1'b1;
            endcase
        end
    end
endmodule
