`timescale 1ns / 10ps
//////////////////////////////////////////////////////////////////////////////////
// Module: sim_sram
// Description: Simulation-only read/write SRAM initialized with UART bootloader.
//              Replaces bootrom for simulation to enable UART->SRAM->CPU path
//              verification. Bootloader receives firmware via UART transceiver
//              and stores to SRAM at 0x1000, then jumps to execute it.
//////////////////////////////////////////////////////////////////////////////////

module sim_sram (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ce,       // Chip Enable
    input  wire [3:0]  we,       // Write Enable (byte lanes)
    input  wire [31:0] addr,     // Word address (already >>2 from system.v)
    input  wire [31:0] din,      // Write data
    output wire [31:0] dataout   // Read data
);

    // 16KB SRAM = 4096 words
    parameter MEM_DEPTH = 4096;
    reg [31:0] mem [0:MEM_DEPTH-1];

    reg [31:0] dout;
    integer i;

    // Initialize memory with bootloader at address 0x000
    // and NOPs everywhere else
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem[i] = 32'h00000013; // NOP

        // ========================================================
        // UART Bootloader Firmware
        // Configures UART transceiver, sends handshake (1,2,3,4),
        // receives 8 words via UART, stores at 0x1000, jumps there
        // ========================================================

        // UART configuration
        mem[12'h000] = 32'h030002B7; // lui   x5,  0x03000     ; t0 = UART base 0x03000000
        mem[12'h001] = 32'h00001EB7; // lui   x29, 0x00001     ; t4 = 0x00001000 (FW dest)
        mem[12'h002] = 32'h00001E37; // lui   x28, 0x00001     ; t3 = 0x00001000 (FW exec)
        mem[12'h003] = 32'h08000313; // addi  x6,  x0, 0x80    ; t1 = 0x80
        mem[12'h004] = 32'h006281A3; // sb    x6,  3(x5)       ; LCR = 0x80 (DLAB=1)
        mem[12'h005] = 32'h00000313; // addi  x6,  x0, 0       ; t1 = 0
        mem[12'h006] = 32'h006280A3; // sb    x6,  1(x5)       ; DLM = 0
        mem[12'h007] = 32'h03600313; // addi  x6,  x0, 0x36    ; t1 = 0x36
        mem[12'h008] = 32'h00628023; // sb    x6,  0(x5)       ; DLL = 0x36 (baud divisor)
        mem[12'h009] = 32'h00300313; // addi  x6,  x0, 3       ; t1 = 3
        mem[12'h00A] = 32'h006281A3; // sb    x6,  3(x5)       ; LCR = 0x03 (8N1, DLAB=0)
        mem[12'h00B] = 32'h0C600313; // addi  x6,  x0, 0xC6    ; t1 = 0xC6
        mem[12'h00C] = 32'h00628123; // sb    x6,  2(x5)       ; FCR = 0xC6 (enable FIFOs)
        mem[12'h00D] = 32'h00800513; // addi  x10, x0, 8       ; word_count = 8

        // Handshake: send bytes 1,2,3,4 to signal "ready"
        mem[12'h00E] = 32'h00100313; // addi  x6,  x0, 1       ; t1 = 1
        mem[12'h00F] = 32'h00500393; // addi  x7,  x0, 5       ; t2 = 5 (loop limit)
        mem[12'h010] = 32'h00628023; // sb    x6,  0(x5)       ; send byte via UART THR
        mem[12'h011] = 32'h00130313; // addi  x6,  x6, 1       ; t1++
        mem[12'h012] = 32'hFE63DCE3; // bge   x7,  x6, -8      ; loop while t2 >= t1

        // loop_: init byte accumulator for next word
        mem[12'h013] = 32'h00400313; // addi  x6,  x0, 4       ; byte_counter = 4
        mem[12'h014] = 32'h00000F93; // addi  x31, x0, 0       ; shift_amount = 0
        mem[12'h015] = 32'h00000F13; // addi  x30, x0, 0       ; accumulated_word = 0

        // loop: poll UART LSR for received data
        mem[12'h016] = 32'h00C28383; // lb    x7,  12(x5)      ; read LSR
        mem[12'h017] = 32'h0013F393; // andi  x7,  x7, 1       ; check DR (data ready) bit
        mem[12'h018] = 32'hFE038CE3; // beq   x7,  x0, -8      ; loop if no data

        // read: get received byte and accumulate
        mem[12'h019] = 32'h0002C583; // lbu   x11, 0(x5)       ; read RBR (received byte)
        mem[12'h01A] = 32'h01F595B3; // sll   x11, x11, x31    ; shift byte to position
        mem[12'h01B] = 32'h00BF0F33; // add   x30, x30, x11    ; accumulate into word
        mem[12'h01C] = 32'h008F8F93; // addi  x31, x31, 8      ; next shift position
        mem[12'h01D] = 32'hFFF30313; // addi  x6,  x6, -1      ; byte_counter--
        mem[12'h01E] = 32'h00030463; // beq   x6,  x0, 8       ; if 4 bytes done -> sw_fw
        mem[12'h01F] = 32'hFDDFF06F; // jal   x0,  -36         ; else back to poll (loop)

        // sw_fw: store assembled word to SRAM
        mem[12'h020] = 32'h01EEA023; // sw    x30, 0(x29)      ; store word at dest ptr
        mem[12'h021] = 32'h004E8E93; // addi  x29, x29, 4      ; dest_ptr += 4
        mem[12'h022] = 32'hFFF50513; // addi  x10, x10, -1     ; word_count--
        mem[12'h023] = 32'h00050463; // beq   x10, x0, 8       ; if all done -> execute_fw
        mem[12'h024] = 32'hFBDFF06F; // jal   x0,  -68         ; else back to loop_

        // execute_fw: jump to loaded firmware at 0x1000
        mem[12'h025] = 32'h000E00E7; // jalr  x1,  x28, 0      ; jump to 0x1000, ra=ret addr
        mem[12'h026] = 32'h0040006F; // jal   x0,  4            ; skip to done

        // done: infinite loop
        mem[12'h027] = 32'h0000006F; // jal   x0,  0            ; halt
    end

    // Synchronous write with byte-lane enables
    always @(posedge clk) begin
        if (ce) begin
            if (we[0]) mem[addr[11:0]][7:0]   <= din[7:0];
            if (we[1]) mem[addr[11:0]][15:8]  <= din[15:8];
            if (we[2]) mem[addr[11:0]][23:16] <= din[23:16];
            if (we[3]) mem[addr[11:0]][31:24] <= din[31:24];
        end
    end

    // Combinational read
    always @(*) begin
        if (ce)
            dout = mem[addr[11:0]];
        else
            dout = 32'h00000013; // NOP when disabled
    end

    assign dataout = dout;

endmodule
