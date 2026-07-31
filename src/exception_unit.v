'timescale 1ns/ps

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
