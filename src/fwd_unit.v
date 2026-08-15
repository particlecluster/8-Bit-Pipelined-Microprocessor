`timescale 1ns / 1ps

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
