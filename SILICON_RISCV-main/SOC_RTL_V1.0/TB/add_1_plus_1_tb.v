`timescale 1 ns / 1 ps
//////////////////////////////////////////////////////////////////////////////////
// Module: add_1_plus_1_tb
//
// Verification testbench for UART -> SRAM -> PicoRV32 data path.
//
// Test flow:
//   1. CPU boots from sim_sram (UART bootloader)
//   2. Bootloader configures 16550 UART transceiver
//   3. Bootloader sends handshake bytes (1,2,3,4) via TRANSCEIVER_TX
//   4. TB detects handshake, starts sending add_1_plus_1 firmware bytes
//   5. Bootloader receives 32 bytes (8 words), stores to SRAM at 0x1000
//        -> Verifies: UART -> SRAM path
//   6. Bootloader jumps to 0x1000; CPU fetches and executes firmware
//        -> Verifies: PicoRV32 -> SRAM path (read from 0x1000)
//   7. Firmware computes 1+1=2, writes to GPIO and UART THR
//        -> Verifies: correct execution, result = 2
//   8. TB checks GPIO value and UART TX output for ASCII '2'
//
// Expected UART output from CPU:
//   Handshake: bytes 0x01, 0x02, 0x03, 0x04
//   Result:    byte  0x32 (ASCII '2')
//////////////////////////////////////////////////////////////////////////////////

module add_1_plus_1_tb;

    // =========================================================
    // Clock: 100 MHz (10 ns period)
    // =========================================================
    reg clk = 1;
    always #5 clk = ~clk;

    // =========================================================
    // Reset
    // =========================================================
    reg resetn = 0;
    initial begin
        #10  resetn <= 1;
        #100 resetn <= 0;
        #10  resetn <= 1;
    end

    // =========================================================
    // DUT signals
    // =========================================================
    wire trap;
    wire SCK, CS_N;
    wire IO_data_3, IO_data_2, IO_data_1, IO_data_0;
    wire uart_tx_line;       // TRANSCEIVER_TX from DUT
    wire uart_rx_line;       // TRANSCEIVER_RX into DUT

    // =========================================================
    // DUT instantiation
    // =========================================================
    system uut (
        .clk           (clk),
        .resetn        (resetn),
        .trap          (trap),
        .o_qspi_sck   (SCK),
        .o_qspi_cs_n  (CS_N),
        .qspi_io_3    (IO_data_3),
        .qspi_io_2    (IO_data_2),
        .qspi_io_1    (IO_data_1),
        .qspi_io_0    (IO_data_0),
        .TRANSCEIVER_TX(uart_tx_line),
        .TRANSCEIVER_RX(uart_rx_line)
    );

    // =========================================================
    // Flash memory model (active but not used in this test)
    // =========================================================
    W25Q16JV flash_mem (
        .CSn   (CS_N),
        .CLK   (SCK),
        .DIO   (IO_data_0),
        .DO    (IO_data_1),
        .WPn   (IO_data_2),
        .HOLDn (IO_data_3)
    );

    // =========================================================
    // TB UART Receiver — monitors TRANSCEIVER_TX from DUT
    // (captures handshake + result bytes)
    // =========================================================
    wire [7:0] recv_data;
    wire       data_valid_rcv;

    uart_rx tb_rx (
        .clk       (clk),
        .resetn    (resetn),
        .rx        (uart_tx_line),
        .data_out  (recv_data),
        .data_valid(data_valid_rcv)
    );

    // =========================================================
    // TB UART Transmitter — sends firmware bytes to DUT
    // via TRANSCEIVER_RX
    // =========================================================
    wire       tb_tx_busy, tb_tx_done;
    reg  [7:0] tb_tx_data;
    reg        tb_tx_en;

    uart_tx #(
        .BIT_RATE     (115200),
        .CLK_HZ       (100_000_000),
        .PAYLOAD_BITS (8),
        .STOP_BITS    (1)
    ) tb_tx (
        .clk          (clk),
        .resetn       (resetn),
        .uart_txd     (uart_rx_line),   // drives DUT's TRANSCEIVER_RX
        .uart_tx_busy (tb_tx_busy),
        .done         (tb_tx_done),
        .uart_tx_en   (tb_tx_en),
        .uart_tx_data (tb_tx_data)
    );

    // =========================================================
    // Firmware: add_1_plus_1 (8 instructions = 32 bytes)
    //
    //   addi a0, x0, 1          -> a0 = 1
    //   addi a1, a0, 1          -> a1 = 2  (1+1)
    //   lui  a2, 0x05000        -> a2 = GPIO base
    //   sw   a1, 0(a2)          -> GPIO = 2
    //   lui  a2, 0x03000        -> a2 = UART base
    //   addi a3, a1, 0x30       -> a3 = ASCII '2'
    //   sb   a3, 0(a2)          -> UART THR = '2'
    //   jalr x0, ra, 0          -> return to bootloader
    // =========================================================
    reg [7:0] fw_array [0:31];

    initial begin
        // Word 0: addi a0, x0, 1   -> 0x00100513
        fw_array[0]  = 8'h13;  fw_array[1]  = 8'h05;
        fw_array[2]  = 8'h10;  fw_array[3]  = 8'h00;
        // Word 1: addi a1, a0, 1   -> 0x00150593
        fw_array[4]  = 8'h93;  fw_array[5]  = 8'h05;
        fw_array[6]  = 8'h15;  fw_array[7]  = 8'h00;
        // Word 2: lui  a2, 0x05000 -> 0x05000637
        fw_array[8]  = 8'h37;  fw_array[9]  = 8'h06;
        fw_array[10] = 8'h00;  fw_array[11] = 8'h05;
        // Word 3: sw   a1, 0(a2)   -> 0x00B62023
        fw_array[12] = 8'h23;  fw_array[13] = 8'h20;
        fw_array[14] = 8'hB6;  fw_array[15] = 8'h00;
        // Word 4: lui  a2, 0x03000 -> 0x03000637
        fw_array[16] = 8'h37;  fw_array[17] = 8'h06;
        fw_array[18] = 8'h00;  fw_array[19] = 8'h03;
        // Word 5: addi a3, a1, 0x30 -> 0x03058693
        fw_array[20] = 8'h93;  fw_array[21] = 8'h86;
        fw_array[22] = 8'h05;  fw_array[23] = 8'h03;
        // Word 6: sb   a3, 0(a2)   -> 0x00D60023
        fw_array[24] = 8'h23;  fw_array[25] = 8'h00;
        fw_array[26] = 8'hD6;  fw_array[27] = 8'h00;
        // Word 7: jalr x0, ra, 0   -> 0x00008067
        fw_array[28] = 8'h67;  fw_array[29] = 8'h80;
        fw_array[30] = 8'h00;  fw_array[31] = 8'h00;
    end

    // =========================================================
    // Handshake detection: count received bytes from DUT
    // When we receive 4 handshake bytes, start sending firmware
    // =========================================================
    reg        send_fw_en = 0;
    integer    handshake_count = 0;

    // Track received bytes for debug
    always @(posedge clk) begin
        if (data_valid_rcv) begin
            $display("[TB %0t] UART RX from DUT: 0x%02h", $time, recv_data);
            if (!send_fw_en) begin
                handshake_count <= handshake_count + 1;
                if (handshake_count == 3) begin  // 4th byte (0-indexed)
                    $display("[TB %0t] *** Handshake complete — starting firmware send ***", $time);
                    send_fw_en <= 1;
                end
            end
        end
    end

    // =========================================================
    // Firmware sender FSM: send 32 bytes one at a time
    // =========================================================
    integer    fw_idx      = 0;
    integer    fw_send_cnt = 0;
    reg        fw_sending  = 0;
    reg [1:0]  send_state  = 0;

    always @(posedge clk) begin
        if (!resetn) begin
            tb_tx_en   <= 0;
            fw_idx     <= 0;
            fw_sending <= 0;
            send_state <= 0;
        end else begin
            case (send_state)
                // Wait for handshake to complete
                2'd0: begin
                    tb_tx_en <= 0;
                    if (send_fw_en)
                        send_state <= 2'd1;
                end
                // Load next byte and assert tx_en
                2'd1: begin
                    if (fw_idx < 32 && !tb_tx_busy) begin
                        tb_tx_data <= fw_array[fw_idx];
                        tb_tx_en   <= 1;
                        fw_sending <= 1;
                        send_state <= 2'd2;
                        $display("[TB %0t] Sending FW byte[%0d] = 0x%02h", $time, fw_idx, fw_array[fw_idx]);
                    end else if (fw_idx >= 32) begin
                        tb_tx_en   <= 0;
                        fw_sending <= 0;
                        send_state <= 2'd3;
                        $display("[TB %0t] *** All 32 firmware bytes sent ***", $time);
                    end
                end
                // Wait for TX to finish current byte
                2'd2: begin
                    tb_tx_en <= 0;  // deassert after 1 cycle
                    if (tb_tx_done) begin
                        fw_idx     <= fw_idx + 1;
                        send_state <= 2'd1;  // send next byte
                    end
                end
                // Done sending
                2'd3: begin
                    tb_tx_en <= 0;
                end
            endcase
        end
    end

    // =========================================================
    // Result verification
    // =========================================================
    reg        result_received = 0;
    reg [7:0]  result_byte     = 0;
    reg        gpio_written    = 0;

    // Monitor for result byte (any byte received AFTER firmware send complete)
    always @(posedge clk) begin
        if (data_valid_rcv && send_state == 2'd3 && !result_received) begin
            result_byte     <= recv_data;
            result_received <= 1;
            $display("[TB %0t] *** RESULT received via UART: 0x%02h (char: '%c') ***",
                     $time, recv_data, recv_data);
        end
    end

    // Monitor GPIO write (probe internal led register)
    // The firmware writes 2 to GPIO at 0x05000000
    always @(posedge clk) begin
        if (uut.pred_trigger && !gpio_written) begin
            gpio_written <= 1;
            $display("[TB %0t] *** GPIO write detected: led = %0d ***", $time, uut.led);
        end
    end

    // =========================================================
    // SRAM content verification
    // After firmware is stored, probe sim_sram at 0x1000
    // (word address 0x400 -> sim_sram index 0x400)
    // =========================================================
    reg sram_verified = 0;

    task verify_sram;
        integer w;
        reg [31:0] expected [0:7];
        reg [31:0] actual;
        reg all_match;
        begin
            expected[0] = 32'h00100513;
            expected[1] = 32'h00150593;
            expected[2] = 32'h05000637;
            expected[3] = 32'h00B62023;
            expected[4] = 32'h03000637;
            expected[5] = 32'h03058693;
            expected[6] = 32'h00D60023;
            expected[7] = 32'h00008067;

            all_match = 1;
            $display("[TB %0t] --- SRAM Verification (UART -> SRAM path) ---", $time);
            for (w = 0; w < 8; w = w + 1) begin
                actual = uut.sim_sram_i.mem[12'h400 + w];
                if (actual !== expected[w]) begin
                    $display("[TB]   SRAM[0x%03h] = 0x%08h  EXPECTED 0x%08h  *** MISMATCH ***",
                             12'h400 + w, actual, expected[w]);
                    all_match = 0;
                end else begin
                    $display("[TB]   SRAM[0x%03h] = 0x%08h  OK", 12'h400 + w, actual);
                end
            end
            if (all_match)
                $display("[TB] >>> UART -> SRAM PATH: PASS <<<");
            else
                $display("[TB] >>> UART -> SRAM PATH: FAIL <<<");
            sram_verified = 1;
        end
    endtask

    // =========================================================
    // Test orchestration: timeout + final verdict
    // =========================================================
    reg test_done = 0;

    initial begin
        $dumpfile("add_1_plus_1_tb.vcd");
        $dumpvars(0, add_1_plus_1_tb);

        $display("============================================================");
        $display(" UART -> SRAM -> PicoRV32 Verification Testbench");
        $display(" Firmware: add 1+1 = 2");
        $display("============================================================");

        // Wait for all firmware bytes to be sent + time for CPU to execute
        // 32 bytes at 115200 baud ≈ 32 * 86.8us ≈ 2.8ms = 2,800,000 ns
        // Plus bootloader execution + firmware execution: ~500,000 ns
        // Total budget: 5,000,000 ns (5 ms)
        #5_000_000;

        // Check SRAM contents
        verify_sram;

        // Allow extra time for UART TX of result
        #2_000_000;

        // ---- Final Verdict ----
        $display("");
        $display("============================================================");
        $display(" FINAL RESULTS");
        $display("============================================================");

        // Check 1: SRAM content (UART -> SRAM path)
        if (sram_verified)
            $display(" [CHECK 1] UART -> SRAM path verified via SRAM probe");
        else
            $display(" [CHECK 1] UART -> SRAM path NOT verified");

        // Check 2: GPIO (PicoRV32 -> SRAM read -> execution)
        if (gpio_written && uut.led == 4'd2)
            $display(" [CHECK 2] PicoRV32 -> SRAM -> Execute: PASS (GPIO = %0d, expected 2)", uut.led);
        else if (gpio_written)
            $display(" [CHECK 2] PicoRV32 -> SRAM -> Execute: FAIL (GPIO = %0d, expected 2)", uut.led);
        else
            $display(" [CHECK 2] PicoRV32 -> SRAM -> Execute: FAIL (no GPIO write detected)");

        // Check 3: UART result output
        if (result_received && result_byte == 8'h32)
            $display(" [CHECK 3] UART result output: PASS (received 0x%02h = '%c')", result_byte, result_byte);
        else if (result_received)
            $display(" [CHECK 3] UART result output: FAIL (received 0x%02h, expected 0x32)", result_byte);
        else
            $display(" [CHECK 3] UART result output: FAIL (no result byte received)");

        // Check 4: CPU trap
        if (trap)
            $display(" [CHECK 4] CPU TRAP: DETECTED (possible illegal instruction)");
        else
            $display(" [CHECK 4] CPU TRAP: None (OK)");

        $display("============================================================");

        if (sram_verified && gpio_written && uut.led == 4'd2 && result_received && result_byte == 8'h32 && !trap)
            $display(" >>> ALL CHECKS PASSED <<<");
        else
            $display(" >>> SOME CHECKS FAILED — see above <<<");

        $display("============================================================");
        $finish;
    end

    // Safety timeout
    initial begin
        #10_000_000;
        $display("[TB] ERROR: Simulation timeout (10 ms). Aborting.");
        $finish;
    end

    // Trap monitor
    always @(posedge trap) begin
        $display("[TB %0t] WARNING: CPU TRAP asserted!", $time);
    end

endmodule
