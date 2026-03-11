`timescale 1 ns / 1 ps

module system_tb;
	reg clk = 1;
	always #5 clk = ~clk;

    wire [7:0] led;
   // wire idx_led;
	reg resetn = 0;

	initial begin #10 resetn <= 1; #100 resetn<=0; #10 resetn<=1; end

	wire trap;
	wire [7:0] out_byte;
	wire out_byte_en;
	
	//spi interface
	wire SCK,CS_N;
	wire IO_data_3,IO_data_2,IO_data_1,IO_data_0;
	
	
    wire uart_tx, uart_rx;
    wire [7:0] recv_data;
    wire data_valid_rcv; 

	system uut (
		.clk        (clk        ),
		.resetn     (resetn     ),
		.trap       (trap       ),
		/*.led(led),
		//.idx_led(idx_led),
		.out_byte   (out_byte   ),
		.out_byte_en(out_byte_en)*/
		.o_qspi_sck(SCK),
		.o_qspi_cs_n(CS_N),
		.qspi_io_3(IO_data_3),
		.qspi_io_2(IO_data_2),
		.qspi_io_1(IO_data_1),
		.qspi_io_0(IO_data_0),
		.TRANSCEIVER_TX(uart_tx),
		.TRANSCEIVER_RX(uart_rx)
		
	);
	
	W25Q16JV flash_mem(.CSn(CS_N), 
	                   .CLK(SCK), 
	                   .DIO(IO_data_0), 
	                   .DO(IO_data_1), 
	                   .WPn(IO_data_2), 
	                   .HOLDn(IO_data_3));
	                   
	// UART receiver instance
    uart_rx rcv (
        .clk(clk),               // 100 MHz clock
        .resetn(resetn),        // active-low reset
        .rx(uart_tx),            // UART serial input
        .data_out(recv_data),    // received byte
        .data_valid(data_valid_rcv)  // high when a full byte is received
    );
    
    wire uart_tx_busy ,done;
    reg [7:0]uart_tx_data;
    reg uart_tx_en;
    reg en;

    uart_tx TX(
           .clk(clk)         , // Top level system clock input.
           .resetn(resetn)      , // Asynchronous active low reset.
         .uart_txd(uart_rx)    , // UART transmit pin.
         .uart_tx_busy(uart_tx_busy), // Module busy sending previous item.
         .done(done), 
         .uart_tx_en(uart_tx_en)  , // Send the data on uart_tx_data
         .uart_tx_data(uart_tx_data)  // The data to be sent
        );
reg [7:0]fw_array[15:0];  

initial begin
  fw_array[0]  = 8'h93;
  fw_array[1]  = 8'h05;
  fw_array[2]  = 8'ha0;
  fw_array[3]  = 8'h00;
  fw_array[4]  = 8'h23;
  fw_array[5]  = 8'h80;
  fw_array[6]  = 8'hb2;
  fw_array[7]  = 8'h00;
  fw_array[8]  = 8'h23;
  fw_array[9]  = 8'h80;
  fw_array[10] = 8'hb2;
  fw_array[11] = 8'h00;
  fw_array[12] = 8'h67;
  fw_array[13] = 8'h80;
  fw_array[14] = 8'h00;
  fw_array[15] = 8'h00;
end
    
integer count;
reg [3:0]fw_counter;
always @(posedge clk)
begin
if(!resetn)begin uart_tx_en<=0;count<=0;fw_counter<=0; end
else begin
 if(!uart_tx_busy &&en)
  begin 
  uart_tx_en<=(count<=18);
  uart_tx_data<=fw_array[fw_counter];
  fw_counter=fw_counter+1;
  count<=count+1; 
  end 
 end
end




    
        always @(posedge clk) begin
        if (data_valid_rcv) begin
           $display("%h",recv_data);   // Print as ASCII character (no newline)
           // $fflush();                 // Flush console buffer immediately
        end
    end
	parameter MAX_CHARS=8;           
	reg [7:0] str_buffer [0:MAX_CHARS-1];
    integer char_count;
    integer i;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            char_count <= 0;
            en<=0;
        end 
        else if (data_valid_rcv) begin
            // Check for Newline character (0x0A = \n)
            if (recv_data == 8'h0A) begin
                // --- DISPLAY BLOCK (Simulation Only) ---
                $write("[UART MONITOR] Received Line: ");
                
                // Loop through the accumulated buffer and print each char
                for (i = 0; i < char_count; i = i + 1) begin
                    $write("%c", str_buffer[i]);
                end
                
                $write("\n"); // Print the final newline to console
                // ---------------------------------------                
                // Reset the buffer counter for the next line
                char_count <= 0; 
            end 
            else begin
                // Accumulate character if buffer isn't full
                if (char_count < MAX_CHARS) begin
                    str_buffer[char_count] <= recv_data;
                    char_count <= char_count + 1;
                    if(char_count==4) en<=1;
                end else begin
                    //$display("[UART MONITOR] Warning: Buffer Overflow! Dropping char.");
                end
            end
        end
    end

endmodule