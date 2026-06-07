module data_mem(
    input        clk,
    input        rst,
    input        mem_read,
    input        mem_write,
    input  [7:0] addr,
    input  [7:0] write_data,
    output [7:0] read_data
);

reg [7:0] mem [0:255];

assign read_data = (mem_read) ? mem[addr] : 8'b0;

integer i;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] <= 8'b0;
    end
    else if (mem_write) begin
        mem[addr] <= write_data;
    end
end

endmodule
