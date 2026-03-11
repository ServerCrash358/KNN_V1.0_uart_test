# =============================================================================
# RISC-V Assembly Driver for Spansion S25FL128S Flash
# Controller: Xilinx AXI Quad SPI IP (in Full Quad I/O Mode)
#
# Operation:
# 1. Tests BRAM & UART: Writes 10, 20 to BRAM, reads them back, sends to UART.
# 2. Enables Quad Mode: Sends WREN (0x06) and WRR (0x01) to set the QE bit.
# 3. Polls WIP Bit: Waits for the flash to be ready after writing.
#used for writing data into flash. Writes didnt succeed.
#

# --- Define Memory Map and Constants ---
.equ BRAM_BASE,            0x00002000
.equ SPI_BASE,             0x20000000
.equ UART_BASE,            0x20020000
.equ UART_TX_OFFSET,       0x4

.equ SPI_SR_OFFSET,        0x64  # Status Register (SR)
.equ SPI_TX_FIFO_OFFSET,   0x68  # Transmit FIFO (TXF)
.equ SPI_RX_FIFO_OFFSET,   0x6C  # Receive FIFO (RXF)
.equ SPI_SSR_OFFSET,       0x70  # Slave Select Register (SSR)

.equ TX_EMPTY_MASK,        0x4   # SR[2]
.equ RX_NOT_EMPTY_MASK,    0x1   # SR[0]
.equ WIP_BIT_MASK,         0x1   # Flash Status Register[0]

.equ FLASH_ADDR_TO_READ,   0x0   # Read from the start of flash

 .text
.global _start

_start:
    # --- 1. Initial Setup ---
    # Set stack pointer to top of BRAM (assuming 4KB BRAM)
    li   sp, 0x00003000

    # Load base addresses into saved registers
    li   s0, 0x00002000      # s0 = BRAM Base
    li   s1, 0x20000000       # s1 = SPI Base
    li   s2, 0x20020000      # s2 = UART Base

    # --- 2. BRAM Store/Load/UART Test ---
    
    # --- 2. ** CORRECTED ** Initialize the AXI SPI Controller ---
    # This step is CRITICAL. The IP powers up disabled.
    # We must enable it, set master mode, and de-assert FIFO resets.
    
    # Step 2a:  . Sets all modes, but holds FIFOs in reset
    #          and inhibits master transactions.
    li   t0, 0x1E6
    sw   t0, 0x60(s1)
    
    # Step 2b: . Takes FIFOs out of reset.
    li   t0, 0x13C
    sw   t0, 0x60(s1)
    
    # Step 2c:. Releases master transaction inhibit.
    #          The IP is now fully enabled and ready.
    li   t0, 0x086
    sw   t0, 0x60(s1)
    #
    # (End of corrected step)
    
    
    # Store 10 and 20
    li   t0, 10
    sw   t0, 0(s0)          # BRAM[0] = 10
    li   t0, 20
    sw   t0, 4(s0)          # BRAM[1] = 20

    # Load 10 and send to UART
    lw   t1, 0(s0)          # t1 = BRAM[0]
    sw   t1, 4(s2) # Write to UART TX
    # Simple delay loop
    li   t0, 5
delay1:
    addi t0, t0, -1
    bnez t0, delay1

    # Load 20 and send to UART
    lw   t1, 4(s0)          # t1 = BRAM[1]
    sw   t1, 4(s2) # Write to UART TX
    li   t0, 5
delay2:
    addi t0, t0, -1
    bnez t0, delay2

    # --- 3. Enable Quad Mode in Flash Chip ---
    # This is the "programmer's responsibility" part.

    # --- Step 3a: Send Write Enable (WREN: 0x06) ---
    li   t0, -2             # 0xFFFFFFFE (Select slave 0)
    sw   t0, 0x70(s1) # Assert CS
wren_tx_wait:
    sw zero,4(s2)
    lw t0,0x6c(s1)
    sw t0,4(s2)
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wren_tx_wait # Wait for TX FIFO empty
    li   t0, 0x06           # Load WREN command
    sw   t0, 0x68(s1) # Send command
wren_end_wait:              # Wait for TX to finish
    lw   t0, 0x64(s1)
    sw t0,4(s2) #display the status

    andi  t0, t0, 0x4
    beq  t0, zero, wren_end_wait
    li   t0, -1             # 0xFFFFFFFF (Deselect all)
    sw   t0, 0x70(s1) # De-assert CS

    # --- Step 3b: Write Registers (WRR: 0x01) to set QE bit ---
    li   t0, -2
    sw   t0, 0x70(s1) # Assert CS
wrr_tx_wait_1:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x4
    beq  t0, zero, wrr_tx_wait_1
    li   t0, 0x01           # Load WRR command
    sw   t0, 0x68(s1) # Send command
wrr_tx_wait_2:
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wrr_tx_wait_2
    sw   zero, 0x68(s1) # Send Data 1: 0x00 for SR1
wrr_tx_wait_3:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x4
    beq  t0, zero, wrr_tx_wait_3
    li   t0, 0xC2  # Send Data 2: 0x02 for CR1 (sets QE bit), 0xC0 for setting LC to 0'b11

    sw   t0, 0x68(s1)
wrr_end_wait:               # Wait for TX to finish
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wrr_end_wait
    li   t0, -1
    sw   t0, 0x70(s1) # De-assert CS
    
# --- Step 3c: Poll Status Register until WIP (Write In Progress) bit is 0 ---
wip_poll_loop:
    li t0, 0X0C6
    sw t0,0x60(s1) #Reset the RX_FIFO to avoid reading garbage values
    li   t0, -2
    sw   t0, 0x70(s1) # Assert CS
wip_tx_wait_1:              # Wait for TX empty
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wip_tx_wait_1
    li   t0, 0x05           # Read Status Reg (RDSR) command
    sw   t0, 0x68(s1)
    
    wrr_end_wait_rdsr:               # Wait for TX to finish
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wrr_end_wait_rdsr
    sw zero, 0x68(s1)     #dumy byte  
    wrr_end_wait_dummy:               # Wait for TX to finish
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wrr_end_wait_dummy   

    li   t0, -1
    sw   t0, 0x70(s1) # De-assert CS
    li   t0, 0x186 #master inhibit
    sw   t0, 0x60(s1)
    
         
 lw t1, 0x6C(s1) # Read DRR (one garbage byte)
 lw t1, 0x6C(s1)
 andi t1,t1,1
 bnez t1,wip_poll_loop
 

uart_tx_full:
    lw t2,0x8(s2) #read the status reg of uart
    andi t2,t2,0x4
    beq t2,zero,uart_tx_full
    sw zero,4(s2)
    sw zero,4(s2)
    
    
 li   t0, 0x1E6 #master inhibit and rest fifos
 sw   t0, 0x60(s1)
 li   t0, -2
sw   t0, 0x70(s1) # Assert CS
li   t0, 0x086
sw   t0, 0x60(s1)
send_WREN:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x4
    beq  t0, zero, send_WREN
    li   t0, 0x06           # WREN
    sw   t0, 0x68(s1)
wren_end_wait_PP:           # Wait for TX to finish
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wren_end_wait_PP
    li   t0, -1
    sw   t0, 0x70(s1) # De-assert CS
    
    
wip_poll_loop_PP:
    li t0, 0X0C6
    sw t0,0x60(s1) #Reset the RX_FIFO to avoid reading garbage values
    li   t0, -2
    sw   t0, 0x70(s1) # Assert CS
wip_tx_wait_1_PP:              # Wait for TX empty
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wip_tx_wait_1_PP
    li   t0, 0x05           # Read Status Reg (RDSR) command
    sw   t0, 0x68(s1)
    
wrr_end_wait_rdsr_PP:               # Wait for TX to finish
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wrr_end_wait_rdsr_PP
    sw zero, 0x68(s1)     #dumy byte  
wrr_end_wait_dummy_PP:               # Wait for TX to finish
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wrr_end_wait_dummy_PP   

    li   t0, -1
    sw   t0, 0x70(s1) # De-assert CS
    li   t0, 0x186 #master inhibit
    sw   t0, 0x60(s1)
    
         
 lw t1, 0x6C(s1) # Read DRR (one garbage byte)
 lw t1, 0x6C(s1)
 andi t1,t1,1
 bnez t1,wip_poll_loop_PP
    
    
    
page_prog_command:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
    bnez  t0 ,page_prog_command
    li   t0, 0x32           # quad page program command
    sw   t0, 0x68(s1)
qio_PP_tx_addr_1:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
    bnez  t0 ,qio_PP_tx_addr_1
    sw   zero, 0x68(s1)  # Addr[23:16]
qio_PP_tx_addr_2:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
    bnez  t0, qio_PP_tx_addr_2
    sw   zero, 0x68(s1)  # Addr[15:8]
qio_PP_tx_addr_3:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
    bnez  t0, qio_PP_tx_addr_3
    sw   zero, 0x68(s1) # Addr[7:0]
    
    
qio_PP_tx_data__1:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
    bnez  t0, qio_PP_tx_data__1
    li t0,10
    sw   t0, 0x68(s1) #data byte 1
qio_PP_tx_dummy_wait:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
    bnez  t0, qio_PP_tx_dummy_wait
    
    
qio_PP_tx_data__2:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
     bnez  t0, qio_PP_tx_data__2
    li t0,20
    sw   t0, 0x68(s1) #data byte 2
    
qio_PP_tx_data__3:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
     bnez  t0, qio_PP_tx_data__3
    li t0,30
    sw   t0, 0x68(s1) #data byte 3

qio_PP_tx_data__4:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
     bnez  t0, qio_PP_tx_data__4
    li t0,40
    sw   t0, 0x68(s1) #data byte 4

    li   t0, -2
    sw   t0, 0x70(s1) # Assert CS    
    #disable master inhibit
    li   t0, 0x086
    sw   t0, 0x60(s1)  
    
wait_PP_tx_empty:
     lw   t0, 0x64(s1)
     andi  t0, t0, 0x4
     beq  t0, zero, wait_PP_tx_empty
    
    li   t0, -1
    sw   t0, 0x70(s1)  # De-assert CS    

wip_poll_loop_PP_WIP:
    li t0, 0X0C6
    sw t0,0x60(s1) #Reset the RX_FIFO to avoid reading garbage values
    li   t0, -2
    sw   t0, 0x70(s1) # Assert CS
wip_tx_wait_1_PP_WIP:              # Wait for TX empty
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wip_tx_wait_1_PP_WIP
    li   t0, 0x05           # Read Status Reg (RDSR) command
    sw   t0, 0x68(s1)
    
wrr_end_wait_rdsr_PP_WIP:               # Wait for TX to finish
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wrr_end_wait_rdsr_PP_WIP
    sw zero, 0x68(s1)     #dumy byte  
wrr_end_wait_dummy_PP_WIP:               # Wait for TX to finish
    lw   t0, 0x64(s1)
    sw t0,4(s2)
    andi  t0, t0, 0x4
    beq  t0, zero, wrr_end_wait_dummy_PP_WIP   

    li   t0, -1
    sw   t0, 0x70(s1) # De-assert CS
    li   t0, 0x186 #master inhibit
    sw   t0, 0x60(s1)
    
         
 lw t1, 0x6C(s1) # Read DRR (one garbage byte)
 lw t1, 0x6C(s1)
 andi t1,t1,1
 bnez t1,wip_poll_loop_PP_WIP

    
    # --- 4. Read First Two Words from Flash (Q Out read Mode) ---
    # IP is configured for Q out read, flash QE bit is set.
    li s3,0x03
    sw s3,0xc(s2)
    li   s3, 0x00000000 # s3 = address to load from the flash
    li   s4, 4                  # s4 = Word count (2 words)
    mv   s5, s0                 # s5 = BRAM destination pointer
    li   t0, 0x1E6 #master inhibit and rest fifos
    sw   t0, 0x60(s1)
  
qio_tx_wait_1:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x4
    beq  t0, zero, qio_tx_wait_1
    li   t0, 0x6B           # Quad out Read command
    sw   t0, 0x68(s1)

    # Send 3-byte Address (from s3)
qio_tx_addr_1:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
    bnez  t0 ,qio_tx_addr_1
    srli t0, s3, 16        # Addr[23:16]
    sw   t0, 0x68(s1)
qio_tx_addr_2:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
    bnez  t0, qio_tx_addr_2
    srli t0, s3, 8         # Addr[15:8]
    sw   t0, 0x68(s1)
qio_tx_addr_3:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
     bnez  t0, qio_tx_addr_3
    sw   s3, 0x68(s1) # Addr[7:0]
    
    
qio_tx_dummy__1:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
     bnez  t0, qio_tx_dummy__1
    sw   zero, 0x68(s1) # zero[7:0]
    
qio_tx_dummy_wait:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
    bnez  t0, qio_tx_dummy_wait
    
    
qio_tx_dummy__2:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
     bnez  t0, qio_tx_dummy__2
    sw   zero, 0x68(s1) # zero[7:0]
    
qio_tx_dummy_wait_2:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8
    bnez  t0, qio_tx_dummy_wait_2
    
    li   t0, -2
    sw   t0, 0x70(s1) # Assert CS 
     
    
    #disable master inhibit
    li   t0, 0x086
    sw   t0, 0x60(s1)  
    
wait_tx_empty:
     lw   t0, 0x64(s1)
     andi  t0, t0, 0x4
     beq  t0, zero, wait_tx_empty
    
    lw   t1, 0x6C(s1) # Read 4 garbage bytes(command+3address bytes)
    lw   t1, 0x6C(s1) 
    lw   t1, 0x6C(s1) 
    lw   t1, 0x6C(s1) 
     

    # --- Read Burst Loop (for s4=2 words) ---
read_burst_loop:
    beq  s4, zero, read_burst_end # If count is 0, we're done
qio_rx_wait:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x4
    beq  t0, zero, qio_rx_wait # Wait for RX FIFO
    
    lw   t1, 0x6C(s1) # Read data word
    sw   t1, 0(s5)          # Store data to BRAM
    sw   t1, 4(s2)          # send to uart   
    addi s5, s5, 4          # Increment BRAM pointer
    addi s4, s4, -1         # Decrement word counter
    
    
    tx_dummy_for_read:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x8       # Poll Tx_Full
    bnez  t0, tx_dummy_for_read # Loop if full
    sw    zero, 0x68(s1)  # Write dummy byte

    # --- 2. POLL FOR RX DATA ---
qio_rx_wait_:
    lw   t0, 0x64(s1)
    andi  t0, t0, 0x1       # ** BUG FIX: Poll Rx_Empty (0x1) **
    bnez t0, qio_rx_wait_    # Loop if Rx_Empty is 1 (EMPTY)
    
    j    read_burst_loop

read_burst_end:
    li   t0, -1
    sw   t0, 0x70(s1) # De-assert CS

    # --- 5. Verify Flash Read (Load from BRAM, Send to UART) ---
    
    # Load first flash word from BRAM
    li   t0, 4
    addi s5,s5,-16
read_back:
    lw   t1, 0(s5)          # t1 = BRAM[0] (data from flash)
    sw   t1, 4(s2) # Write to UART TX 
    addi t0, t0, -1
    addi s5,s5,4
    bnez t0, read_back
sw zero,4(s2)
sw zero,4(s2)    # --- 6. Done ---
done:
    j    done               # Infinite loop
