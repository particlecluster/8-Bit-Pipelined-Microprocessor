module data_mem(

    input clk,

    input mem_read,
    input mem_write,

    input [7:0] addr,

    input [7:0] write_data,

    output [7:0] read_data

);

reg [7:0] mem [0:255];

assign read_data =
        (mem_read) ? mem[addr] : 8'b0;

always @(posedge clk)
begin

    if(mem_write)
        mem[addr] <= write_data;

end

endmodule
