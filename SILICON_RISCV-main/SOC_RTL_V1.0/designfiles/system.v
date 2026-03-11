`timescale 1ns / 10ps
//modified version of system.v (To integtrate BRAM with picorv32 native-memory interface)
//memory mapped architecture (*Native interface based*)
module system (
	input            wire clk,
	input            wire resetn,
	output           wire trap,
    output    wire uart_tx_busy,
	output    wire uart_txd,
	output reg [4:0] outp_idx,
	output reg [3:0] outp_label,
	input wire switch,
	
    //FLASH-SPI controller interface
	/*output wire		o_qspi_sck,
    output wire		o_qspi_cs_n,
    output wire	[1:0]o_qspi_mod,
    output wire	[3:0]o_qspi_dat,
    input  wire	[3:0]i_qspi_dat*/
    output wire		o_qspi_sck,
    output wire		o_qspi_cs_n,
	inout  wire     qspi_io_3,
	inout  wire     qspi_io_2,
	inout  wire     qspi_io_1,
	inout  wire     qspi_io_0,
	
	
	// transceiver signals
	output wire TRANSCEIVER_TX,
	input wire TRANSCEIVER_RX

);
	
//mem_size parameter to determine range of valid BRAM address space
//mem_addr must be smaller than this, for data to be written onto BRAM
	parameter MEM_SIZE = 14088;
	//memory mapped locations    
    parameter GPIO_memory_mapped_address = 32'h0500_0000; // memory mapping for LED's - maybe extended to other GPIO's later
	parameter UART_memory_mapped_address = 32'h0300_0000; // memory mapped location for UART module
	parameter COUNTER_memory_mapped_address = 32'h0400_0000; //memory mapped location for counter to which start sequnce needs to be written
	parameter COUNTER_Value_address = 32'h0400_0004;   //memory mapped location for counter to which stop sequnce needs to be written
	
	parameter SPI_CTRL_REG=32'h0010_0000; //memory mapped location for SPI CSR
	parameter SPI_ACCESS_REG_BASE=32'h0100_0000; //memory mapped location for SPI DATA 
	parameter SPI_ACCESS_REG_END=32'h01FF_FFFF; //memory mapped location for SPI DATA 
	
	parameter UART_TRANSCEIVER_REG_BASE = 32'h0300_0000; //memory mapped location for UART Transceiver
	parameter UART_TRANSCEIVER_REG_END = 32'h0300_00FF; //memory mapped location for UART Transceiver
	/*parameter UART_TRANSCEIVER_CSR_BASE= 0;
	parameter UART_TRANSCEIVER_CSR_END= 0;*/




    
    //UART signals
reg uart_tx_en;
reg [7:0] uart_tx_data;
wire done;
	
wire mem_valid;
wire mem_instr;
reg mem_ready;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0] mem_wstrb;
reg [31:0] mem_rdata;
	
reg [31:0] m_read_data;
reg m_read_en;

wire mem_la_read;
wire mem_la_write;
wire [31:0] mem_la_addr;
wire [31:0] mem_la_wdata;
wire [3:0] mem_la_wstrb;
	

	picorv32 picorv32_core (
		.clk         (clk         ),
		.resetn      (resetn      ),
		.trap        (trap        ),
		.mem_valid   (mem_valid   ),
		.mem_instr   (mem_instr   ),
		.mem_ready   (mem_ready   ),
		.mem_addr    (mem_addr    ),
		.mem_wdata   (mem_wdata   ),
		.mem_wstrb   (mem_wstrb   ),
		.mem_rdata   (mem_rdata   ),
		.mem_la_read (mem_la_read ),
		.mem_la_write(mem_la_write),
		.mem_la_addr (mem_la_addr ),
		.mem_la_wdata(mem_la_wdata),
		.mem_la_wstrb(mem_la_wstrb)
	);


//Bram signlas
reg [31:0] B_mem_wdata;
reg [3:0] w_en; // w_en<=mem_wstrb
wire [31:0] B_mem_rdata;
reg [31:0]B_mem_rdata_latched; //to add one clk cycle delay
wire bram_valid = mem_valid;
reg bram_valid_r; 
    
  
//signals for buffer logic - LED display  
reg [3:0]led;
reg pred_trigger;
reg [79:0]buffer;
reg [27:0]count;
//reg [7:0]count;  //for RTL simulation
reg [4:0] idx_count=0; // output index value(test image index) 
  
  
//SPI registers   
reg [23:0]spi_adress;
reg spi_mem_valid;
reg addr_is_ctrl;

wire [31:0]flash_rdata;
wire flash_ready;

//bridge to controller siganls
parameter AW=22;
wire            i_wb_cyc;
wire            i_wb_stb;
wire            i_wb_ctrl_stb;
wire            i_wb_we;
wire  [AW-1:0]  i_wb_addr;
wire  [31:0]    i_wb_wdata;

// Wishbone response signals (controller -> bridge)
wire           o_wb_stall;
wire           o_wb_ack;
wire [31:0]    o_wb_data;


//spi interface signals
     wire	[1:0]o_qspi_mod;
     wire	[3:0]o_qspi_dat;
     wire	[3:0]i_qspi_dat;
     
     
//UART TRANSCEIVER SIGNALS
reg is_uart_access;
reg uart_transceiver_valid;
wire uart_transceiver_ready;
wire [31:0]uart_txrx_rdata;


    
always @(posedge clk)
  begin
      if(!resetn) 
        begin 
          buffer <= 80'h00000000000000000000;
          outp_label<=0; 
          outp_idx<=0; 
          count<=0;
	  idx_count<=0;  //set the index count value back to zero on reset
         end 
   
      else if(switch) 
        begin  
        if(count==28'h1000000)   
	//if(count==15) //for RTL simulation 
            begin 
             if(idx_count<20)
                begin 
                      outp_idx<=idx_count;
                      idx_count <=idx_count+1;
                      outp_label<=buffer[79:76];  
                      buffer<={buffer[75:0],buffer[79:76]}; 
                end 
              else 
                begin 
                 idx_count<=0; 
                end 
            end 
            count<=count+1;
         end
    
      else if(pred_trigger)
        begin 
          buffer<={buffer[75:0],led};// shift buffer left by 4 bits and store the new predicted label 
        end 
    
    else 
      begin buffer<=buffer; end
   
  end
     
 
reg uart_tx_en_r; // Register to block repeated enables

always @(posedge clk) 
 begin
  if (!resetn) 
   begin
    B_mem_rdata_latched <= 0;
    led <= 0;
    pred_trigger <= 0;
    uart_tx_data <= 0;
    uart_tx_en <= 0;
    m_read_en <= 0;
    w_en <= 0;
   end 
  else 
   begin
    // Default assignments
    m_read_en <= 0;
    pred_trigger <= 0;
    w_en <= 0;
    uart_tx_en <= 0;  // Deassert every cycle unless triggered below
    spi_mem_valid<=0;
    is_uart_access<=0;
    uart_transceiver_valid<=0;

    // 1. BRAM Write (data write into memory)
    if (mem_valid && !mem_ready && |mem_wstrb && (mem_addr < MEM_SIZE)) begin
      w_en <= mem_wstrb;
      pred_trigger <= 0;
      end
      
    // 2. GPIO Write (store label into LED buffer)
    else if (!mem_instr && mem_valid && mem_ready && (mem_addr == GPIO_memory_mapped_address)) begin
      led[3:0] <= mem_wdata[3:0];
      pred_trigger <= 1;
     end 

    // 3. UART transceiver (16550) — must be checked BEFORE simple UART
    //    since both share base address 0x03000000. This ensures DLL/THR
    //    writes reach the 16550 instead of being consumed by simple UART.
    else if((mem_addr>=UART_TRANSCEIVER_REG_BASE)&&(mem_addr<=UART_TRANSCEIVER_REG_END)) begin 
    is_uart_access<=1;
    uart_transceiver_valid<=mem_valid;
    end

    // 4. Simple UART Write (legacy, now unreachable for transceiver range)
    else if (mem_valid && !mem_ready && |mem_wstrb && (mem_addr == UART_memory_mapped_address)) 
     begin
      if (!done) begin
        uart_tx_data <= mem_wdata[7:0];
        uart_tx_en <= 1;        // One-cycle strobe
      end
      else 
        uart_tx_en <= 0;
      end
  //5. SPI FLASH controller
    else if(mem_valid&&!mem_instr&&((mem_addr>=SPI_ACCESS_REG_BASE)&&(mem_addr<=SPI_ACCESS_REG_END)|| mem_addr== SPI_CTRL_REG)) begin
    //spi_adress<=mem_addr[23:0];
    addr_is_ctrl<= (mem_addr== SPI_CTRL_REG);
    spi_mem_valid<=mem_valid;
    end
    
    
  end
end


`ifdef FOR_FPGA   
//BRAM instantiation
  blk_mem_gen_0 bram(
  .clka(clk),
  .ena(bram_valid),
  .wea(w_en),
  .addra(mem_addr>>2),
  .dina(mem_wdata),
  .douta(B_mem_rdata)
);
`else
 sim_sram sim_sram_i(
   .clk(clk),
   .rst_n(resetn),
   .ce(bram_valid),
   .we(w_en),
   .addr(mem_addr>>2),
   .din(mem_wdata),
   .dataout(B_mem_rdata)
 );
`endif

// Handle BRAM's synchronous read latency
  always @(posedge clk or negedge resetn) 
    begin
        if (!resetn) 
        begin
            bram_valid_r <= 1'b0;
        end 
        else begin
            
            bram_valid_r <= bram_valid;
        end
    end

  always @(*)
    begin 
          mem_ready = spi_mem_valid ? flash_ready : uart_transceiver_valid ? uart_transceiver_ready : bram_valid_r || (mem_valid && !bram_valid); 
          mem_rdata = spi_mem_valid ? flash_rdata : uart_transceiver_valid ? uart_txrx_rdata : bram_valid_r ? B_mem_rdata :32'h000000000; // removed 32'h0
    end
     
     
//UART module instance
uart_tx #(
    .BIT_RATE     (9600),       // Set desired UART baud rate
    .CLK_HZ       (100_000_000),   // Your system clock in Hz
    .PAYLOAD_BITS (8),            // Standard 8-bit UART
    .STOP_BITS    (1)             // 1 stop bit (8N1 format)
) uart_tx (
    .clk           (clk),         // System clock
    .resetn        (resetn),      // Active-low reset
    .uart_txd      (uart_txd),    // UART serial transmit output
    .uart_tx_busy  (uart_tx_busy),// Indicates UART is busy
    .uart_tx_en    (uart_tx_en),  // Strobe signal to send data
    .uart_tx_data  (uart_tx_data),
    .done(done) // 8-bit data to transmit
);


//UART TRANSCEIVER
soc_uart_top  UART_TX_RX(
    // System Inputs
    .clk(clk),
    .resetn(resetn),

    // RISC-V Native Memory Interface
    .mem_valid(uart_transceiver_valid),
    //.mem_instr, // Ignored for UART (data access only)
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(uart_txrx_rdata),
    .mem_ready(uart_transceiver_ready),
    .is_uart_access(is_uart_access),

    // External UART Pins (To Pads)
    .stx_pad_o(TRANSCEIVER_TX),
    .srx_pad_i(TRANSCEIVER_RX)
);



//PICO-SPI Wishbone bridge
mem_to_wb_bridge core_wb_bridge(
        .clk         (clk         ),
		.resetn      (resetn      ),
		.cpu_mem_valid   (spi_mem_valid   ),
		.cpu_mem_instr   (mem_instr   ),
		.cpu_mem_ready   (flash_ready   ),
		.cpu_mem_addr    (mem_addr    ),
		.cpu_mem_wdata   (mem_wdata   ),
		.cpu_mem_wstrb   (mem_wstrb   ),
		.cpu_mem_rdata_   (flash_rdata   ),
		//outputs to controller
		.i_wb_cyc(i_wb_cyc),
        .i_wb_data_stb(i_wb_stb),
        .i_wb_ctrl_stb(i_wb_ctrl_stb),
        .i_wb_we(i_wb_we),
        .i_wb_addr(i_wb_addr),
        .i_wb_data(i_wb_wdata),
        //inputs to bridge
        .o_wb_stall(o_wb_stall),
        .o_wb_ack(o_wb_ack),
        .o_wb_data(o_wb_data),
        .addr_is_ctrl(addr_is_ctrl)
);

//SPI
qflexpress #(
	// .AW( ),   // Address width
	// .DW( )    // Data width
) U_QFLEX (
	// Clock & Reset
	.i_clk          (clk),
	.i_reset        (resetn),

	// Wishbone interface
	.i_wb_cyc       (i_wb_cyc),
	.i_wb_stb       (i_wb_stb),
	.i_cfg_stb      (i_wb_ctrl_stb),
	.i_wb_we        (i_wb_we),
	.i_wb_addr      (i_wb_addr),
	.i_wb_data      (i_wb_wdata),

	.o_wb_stall     (o_wb_stall),
	.o_wb_ack       (o_wb_ack),
	.o_wb_data      (o_wb_data),

	// QSPI interface
	.o_qspi_sck     (o_qspi_sck),
	.o_qspi_cs_n    (o_qspi_cs_n),
	.o_qspi_mod     (o_qspi_mod),
	.o_qspi_dat     (o_qspi_dat),
	.i_qspi_dat     (i_qspi_dat)

	// Debug signals (optional)
	// .o_dbg_trigger ( ),
	// .o_debug       ( )
);


wire oe_dat0 = (o_qspi_mod == 2'b10) || (o_qspi_mod == 2'b00);
wire oe_dat1 = (o_qspi_mod == 2'b10);
wire oe_dat2 = (o_qspi_mod == 2'b10);
wire oe_dat3 = (o_qspi_mod == 2'b10);
 

assign qspi_io_0 = oe_dat0 ? o_qspi_dat[0] : 1'bz;
assign qspi_io_1 = oe_dat1 ? o_qspi_dat[1] : 1'bz;
assign qspi_io_2 = oe_dat2 ? o_qspi_dat[2] : 1'bz;
assign qspi_io_3 = oe_dat3 ? o_qspi_dat[3] : 1'bz;

assign i_qspi_dat = {qspi_io_3,qspi_io_2,qspi_io_1,qspi_io_0};

endmodule        
          
