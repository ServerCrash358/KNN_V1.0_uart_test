`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/09/2025 05:33:15 PM
// Design Name: 
// Module Name: CPU_SPI_WB_bridge
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

module mem_to_wb_bridge #(
    parameter integer AW = 22, // must match: wbqspiflash AW = ADDRESS_WIDTH-2
    parameter [31:0] CTRL_BASE = 32'h0010_0000 , // base address for control regs
    parameter [31:0] CTRL_MASK = 32'hFFFF0000  // mask to select control region
)(
    input  wire           clk,
    input  wire           resetn,
    // CPU side (core's native memory interface)
    input  wire           cpu_mem_valid,
    input  wire           cpu_mem_instr, // not used here, available for optimization
    output reg            cpu_mem_ready,
    input  wire [31:0]    cpu_mem_addr,
    input  wire [31:0]    cpu_mem_wdata,
    input  wire  [3:0]    cpu_mem_wstrb,
    output wire  [31:0]    cpu_mem_rdata_,
    // Wishbone (slave) side expected by wbqspiflash
    output reg            i_wb_cyc,
    output reg            i_wb_data_stb,
    output reg            i_wb_ctrl_stb,
    output reg            i_wb_we,
    output reg  [(AW-1):0] i_wb_addr,
    output reg  [31:0]    i_wb_data,
    input  wire           o_wb_stall,
    input  wire           o_wb_ack,
    input  wire [31:0]    o_wb_data,
    input wire   addr_is_ctrl
);

    localparam IDLE = 1'b0, BUSY = 1'b1;
    reg state;
    reg [31:0]cpu_mem_rdata;
    //reg cpu_mem_ready;
    // Helper: whether current cpu address targets control registers
    //wire addr_is_ctrl = ((cpu_mem_addr & CTRL_MASK) == CTRL_BASE);

    // Word address extraction: drop two low bits
    // Note: if AW is smaller than (32-2) this truncates higher bits.
    wire [(AW-1):0] cpu_word_addr = cpu_mem_addr[AW+1:2];

    // Simple single-transaction FSM
    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            i_wb_cyc <= 1'b0;
            i_wb_data_stb <= 1'b0;
            i_wb_ctrl_stb <= 1'b0;
            i_wb_we <= 1'b0;
            i_wb_addr <= { (AW){1'b0} };
            i_wb_data <= 32'h00000000;
            cpu_mem_ready <= 1'b0;
            cpu_mem_rdata <= 32'h00000000;
        end else begin
            // Default: clear one-cycle response signal
            cpu_mem_ready <= 1'b0;

            case (state)
            IDLE: begin
                // Start a new transaction if the CPU requests it AND the
                // slave is not currently signaling stall (e.g. during init).
                // This avoids asserting cyc/stb in a cycle where o_wb_stall==1
                // (useful if the slave is in a startup/maintenance state).
                if (cpu_mem_valid && !o_wb_stall) begin
                    i_wb_cyc <= 1'b1;
                    i_wb_we <= (|cpu_mem_wstrb) ? 1'b1 : 1'b0;
                    i_wb_addr <= cpu_word_addr;
                    i_wb_data <= cpu_mem_wdata;
                    if (addr_is_ctrl) begin
                        i_wb_ctrl_stb <= 1'b1;
                        i_wb_data_stb <= 1'b0;
                    end else begin
                        i_wb_data_stb <= 1'b1;
                        i_wb_ctrl_stb <= 1'b0;
                    end
                    // move to BUSY and wait for ack
                    state <= BUSY;
                end
                // else remain idle
            end

            BUSY: begin
                // Keep strobes asserted while slave stalls. When slave
                // asserts o_wb_ack, that finishes the transaction.
                if (o_wb_ack) begin
                    // Deliver read data back to CPU (for reads)
                    cpu_mem_rdata <= o_wb_data;
                    cpu_mem_ready <= 1'b1; // one-cycle ready pulse
                    // Clear WB signals in the next cycle
                    i_wb_cyc <= 1'b0;
                    i_wb_data_stb <= 1'b0;
                    i_wb_ctrl_stb <= 1'b0;
                    i_wb_we <= 1'b0;
                    state <= IDLE;
                end else begin
                    // keep asserting cyc to hold the transaction; slave
                    // may assert o_wb_stall meanwhile.
                    i_wb_cyc <= 1'b1;
                end
            end

            endcase
        end
    end
    
    
    assign cpu_mem_rdata_=cpu_mem_rdata;
    //assign cpu_mem_ready_=cpu_mem_ready;

endmodule