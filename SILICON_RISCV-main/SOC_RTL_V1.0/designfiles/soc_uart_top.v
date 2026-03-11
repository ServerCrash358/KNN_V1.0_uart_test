`timescale 1ns / 10ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/12/2025 01:09:33 AM
// Design Name: 
// Module Name: soc_uart_top
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

module soc_uart_top (
    // System Inputs
    input wire clk,
    input wire resetn,

    // RISC-V Native Memory Interface
    input  wire        mem_valid,
    input  wire        mem_instr, // Ignored for UART (data access only)
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [ 3:0] mem_wstrb,
    output wire [31:0] mem_rdata,
    output wire        mem_ready,
    input  wire        is_uart_access,    
    // External UART Pins (To Pads)
    output wire stx_pad_o,
    input  wire srx_pad_i
);

    // ---------------------------------------------------------
    // 1. Address Decoding
    // ---------------------------------------------------------
    // Let's say UART is at 0x1000_0000.
    // We check if the top 16 bits match 0x1000.


    // ---------------------------------------------------------
    // 2. Signal Mapping (The Bridge)
    // ---------------------------------------------------------
    
    // Reset: Invert RISC-V resetn for Wishbone
    wire wb_rst = ~resetn;

    // Cycle & Strobe: Assert when CPU says Valid AND Address matches UART
    wire wb_cyc = mem_valid && is_uart_access;
    wire wb_stb = mem_valid && is_uart_access;

    // Write Enable: If wstrb is not 0, it's a write. Else read.
    wire wb_we  = (mem_wstrb != 4'b0000);

    // Address: Drop bottom 2 bits for 32-bit word alignment
    // UART Reg 0 = 0x10000000, UART Reg 1 = 0x10000004
    wire [4:0] wb_adr = wb_we? mem_addr[4:0] :(mem_addr[7:0]==8'h08)? 5'h04 :(mem_addr[7:0]==8'h0C)? 5'h05 :(mem_addr[7:0]==8'h10)? 5'h06: mem_addr[4:0]; 

    // Data Mappings
    wire [31:0] wb_dat_i = mem_wdata;
    wire [31:0] wb_dat_o_uart;
    wire [3:0]  wb_sel = wb_we ? mem_wstrb : (mem_addr[7:0]==8'h08)? 4'b0001 : (mem_addr[7:0]==8'h0C) ? 4'b0010 : (mem_addr[7:0]==8'h10)? 4'b0100 : 4'b0001 ;

    // Handshake Return
    // If we aren't accessing UART, ready should be 0 (or handled by other slaves)
    // Here we gate it so 'mem_ready' only goes high if UART ACKs.
    wire wb_ack;
    assign mem_ready = wb_ack && is_uart_access;
    

    reg [31:0]aligned_data;
    
    // Read Data Muxing
    // Only drive rdata if this slave was selected, otherwise 0 (or bus mux logic)
    assign mem_rdata = is_uart_access ? aligned_data : 32'b0;
    
    
    //Data Steering logic based on w_sel
    always @(*)
    begin
    case(wb_sel)
    4'b0001: aligned_data={24'b0, wb_dat_o_uart[7:0]};
    4'b0010: aligned_data ={24'b0,wb_dat_o_uart[15:8]};
    4'b0100: aligned_data={24'b0,wb_dat_o_uart[23:16]};
    4'b1000: aligned_data={24'b0,wb_dat_o_uart[31:24]};
    default: aligned_data = wb_dat_o_uart;
    endcase
    
    
    end

    // ---------------------------------------------------------
    // 3. UART Instance
    // ---------------------------------------------------------
    // IMPORTANT: synchronizer for srx_pad_i should be here or inside uart_top
    
    reg srx_sync_1, srx_sync_2;
    always @(posedge clk) begin
        srx_sync_1 <= srx_pad_i;
        srx_sync_2 <= srx_sync_1;
    end

    uart_top uart_inst (
        .wb_clk_i(clk),
        .wb_rst_i(wb_rst),
        
        .wb_adr_i(wb_adr),
        .wb_dat_i(wb_dat_i),
        .wb_dat_o(wb_dat_o_uart),
        .wb_we_i (wb_we),
        .wb_stb_i(wb_stb),
        .wb_cyc_i(wb_cyc),
        .wb_ack_o(wb_ack),
        .wb_sel_i(wb_sel),
        
        .int_o(), // Interrupt output - Connect to PLIC/CPU if needed
        
        // External Pins
        .stx_pad_o(stx_pad_o),
        .srx_pad_i(srx_sync_2), // Use Synced signal!
        
        // Tie off unused Modem signals
        .rts_pad_o(), 
        .cts_pad_i(1'b0), // Clear To Send = Active
        .dtr_pad_o(), 
        .dsr_pad_i(1'b0), 
        .ri_pad_i (1'b1),
        .dcd_pad_i(1'b0)
    );

endmodule