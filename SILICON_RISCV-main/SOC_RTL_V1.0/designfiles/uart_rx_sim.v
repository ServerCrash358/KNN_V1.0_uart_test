`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 14.12.2025 02:47:19
// Design Name: 
// Module Name: uart_rx_sim
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


module uart_rx (
    input        clk,          // 100 MHz clock
    input        resetn,       // active-low reset
    input        rx,           // UART serial input
    output reg [7:0] data_out, // received byte
    output reg   data_valid    // high when a full byte is received
);
    // ------------------------------------------
    // Baud rate timing parameters
    // ------------------------------------------
    // Baud rate = 9600
    // Clock frequency = 100 MHz
    // Clocks per bit = 100e6 / 9600 = 10416.67 ? 10417
    parameter CLKS_PER_BIT = 868;

    // FSM states
    localparam [2:0]
        IDLE       = 3'b000,
        START_BIT  = 3'b001,
        DATA_BITS  = 3'b010,
        STOP_BIT   = 3'b011,
        CLEANUP    = 3'b100;

    reg [2:0]  state = IDLE;
    reg [13:0] clk_count = 0;     // to count up to 10417
    reg [2:0]  bit_index = 0;     // 8 bits = 0-7
    reg [7:0]  rx_shift = 0;
    reg        rx_sync1, rx_sync2;

    // ------------------------------------------
    // Input synchronization (avoid metastability)
    // ------------------------------------------
    always @(posedge clk) begin
        rx_sync1 <= rx;
        rx_sync2 <= rx_sync1;
    end

    // ------------------------------------------
    // UART RX State Machine
    // ------------------------------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            data_valid <= 0;
            data_out <= 8'b0;
        end else begin
            case (state)
                // Wait for start bit
                IDLE: begin
                    data_valid <= 0;
                    if (rx_sync2 == 1'b0) begin
                        state <= START_BIT;
                        clk_count <= 0;
                    end
                end

                // Confirm start bit in middle of bit period
                START_BIT: begin
                    if (clk_count == (CLKS_PER_BIT - 1) / 2) begin
                        if (rx_sync2 == 1'b0) begin
                            clk_count <= 0;
                            bit_index <= 0;
                            state <= DATA_BITS;
                        end else
                            state <= IDLE; // false start
                    end else
                        clk_count <= clk_count + 1;
                end

                // Receive 8 data bits
                DATA_BITS: begin
                    if (clk_count < CLKS_PER_BIT - 1)
                        clk_count <= clk_count + 1;
                    else begin
                        clk_count <= 0;
                        rx_shift[bit_index] <= rx_sync2;

                        if (bit_index == 3'd7)
                            state <= STOP_BIT;
                        else
                            bit_index <= bit_index + 1;
                    end
                end

                // Stop bit
                STOP_BIT: begin
                    if (clk_count < CLKS_PER_BIT - 1)
                        clk_count <= clk_count + 1;
                    else begin
                        data_out <= rx_shift;
                        data_valid <= 1'b1;
                        clk_count <= 0;
                        state <= CLEANUP;
                    end
                end

                // Hold valid for one cycle
                CLEANUP: begin
                    state <= IDLE;
                    data_valid <= 0;
                end
            endcase
        end
    end
endmodule

