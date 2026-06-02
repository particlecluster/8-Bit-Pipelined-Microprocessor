module prog_counter(

    input clk,
    input rst,

    input [7:0] next_pc,

    output reg [7:0] pc

);

always @(posedge clk or posedge rst)
begin

    if(rst)
        pc <= 8'd0;

    else
        pc <= next_pc;

end

endmodule
