`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/05/2026 07:51:03 PM
// Design Name: 
// Module Name: bootrom
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
// Auto-generated 12-bit ASIC Boot ROM
// Total Instructions: 42
// Memory Space: 16KB (4096 words)

module bootrom (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] addr,  // word address from CPU
    input  wire        ce,    // Chip Enable
    output wire [31:0] dataout   // 32-bit instruction output
);
   
    // Internal status register (Sticky bit sets at end of ROM)
    reg boot_done_reg;
    reg [31:0]dout;

    // --- Combinational Lookup ROM ---
    // addr[13:2] extracts the 12-bit word index
    always @(*) begin
        if (ce) begin
            case (addr[11:0])
                12'h000: dout = 32'h030002b7;
                12'h001: dout = 32'h00001eb7;
                12'h002: dout = 32'h00001e37;
                12'h003: dout = 32'h08000313;
                12'h004: dout = 32'h006281a3;
                12'h005: dout = 32'h00000313;
                12'h006: dout = 32'h006280a3;
                12'h007: dout = 32'h03600313;
                12'h008: dout = 32'h00628023;
                12'h009: dout = 32'h00300313;
                12'h00A: dout = 32'h006281a3;
                12'h00B: dout = 32'h0c600313;
                12'h00C: dout = 32'h00628123;
                12'h00D: dout = 32'h030002b7;
                12'h00E: dout = 32'h00100313;
                12'h00F: dout = 32'h00500393;
                12'h010: dout = 32'h00628023;
                12'h011: dout = 32'h00130313;
                12'h012: dout = 32'hfe63dce3;
                12'h013: dout = 32'h0000006f;

                default: dout = 32'h00000013; // RISC-V NOP
            endcase
        end else begin
            dout = 32'h00000013; // Default to NOP when disabled
        end
    end
    
    assign dataout = dout;
    
    // --- Internal Status Logic ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            boot_done_reg <= 1'b0;
        end else if (ce && (addr == 32'h000000A4)) begin
            boot_done_reg <= 1'b1;
        end
    end

endmodule
