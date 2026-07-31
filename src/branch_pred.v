`timescale 1ns / 1ps

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
        if (!rst && ex_is_branch) begin
            valid_btb[ex_idx]   <= 1;
            btb_tag[ex_idx]     <= ex_pc;
            btb_target[ex_idx]  <= ex_actual_target;
            bht[ex_idx]         <= ex_branch_taken;
        end
    end
endmodule
