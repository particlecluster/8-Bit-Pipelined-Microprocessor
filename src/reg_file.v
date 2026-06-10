module reg_file(

    input clk,
    input rst,

    input [2:0] rs1,
    input [2:0] rs2,
    input [2:0] rs3,

    input [2:0] rd,
    input [7:0] wd,

    input reg_write, // write enable

    output [7:0] rd1,
    output [7:0] rd2,
    output [7:0] rd3

);

reg [7:0] regs [0:7];

integer i;

initial begin
    for(i = 0; i < 8; i = i + 1)
        regs[i] = 8'd0;
end

assign rd1 = (rs1 == 3'd0) ? 8'd0 : regs[rs1];
assign rd2 = (rs2 == 3'd0) ? 8'd0 : regs[rs2];
assign rd3 = (rs3 == 3'd0) ? 8'd0 : regs[rs3];


always @(posedge clk) begin
    if(reg_write && rd != 3'd0)
        regs[rd] <= wd;
end

endmodule
