module instr_mem(

    input  [7:0] addr,

    output [15:0] instr

);

reg [15:0] mem [0:255];

initial begin

  $readmemh("program.hex", mem);// program hex is a file with the instructions in hex format, this basically loads instr in mem

end

assign instr = mem[addr];

endmodule
