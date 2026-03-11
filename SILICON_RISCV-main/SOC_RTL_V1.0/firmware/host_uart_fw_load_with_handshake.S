#With hand shake protocol.
# A Simple program that loads firmware from uart ,stores at memory location starting from 0x1000, then jumps to that location ,executes and returns back to "done" loop.
# The bit 0 of lsr becomes 1 if first value gets filled in recieve fifo, so check for the bit 1, then read that value,bit becomes zero until a next value arrives. 
# Each time loop label is called it accumulates 4 bytes to a word and stores into bram. 
# x10 is the counter to set number of words to load for each uart packet recieved from the host/tb.
#

 .text
.globl _start
_start:

    # -------------------------------------
    # UART_BASE = 0x03000000
    # -------------------------------------
    li t0, 0x03000000
    li t4, 0x00001000 
    li t3, 0x00001000 #store the loaded firmware at t3



# ============================================================
# 1. Disable interrupts  (IER = 0)
# ============================================================
    #li    t1, 0x00
    #sb    t1, 0x04(t0)


# ============================================================
# 2. Enable Divisor Latch Access (DLAB=1)  LCR = 0x80
# ============================================================
    li    t1, 0x80
    sb    t1, 0x03(t0)


# ============================================================
# 3. Set baud divisor for 115200 @ 100 MHz
#     DLL = 0x36
#     DLM = 0x00
# ============================================================

    li    t1, 0x00
    sb    t1, 0x01(t0)              # DLM
    li    t1, 0x36
    sb    t1, 0x00(t0)              # DLL




# ============================================================
# 4. Set line for 8N1 (DLAB=0)   LCR = 0x03
# ============================================================
    li    t1, 0x03
    sb    t1, 0x03(t0)


# ============================================================
# 5. Enable FIFO, clear FIFOs  FCR = 0xC1
# ============================================================
    li    t1, 0xC6
    sb    t1, 0x02(t0)


# ============================================================
# 6. Disable modem control (MCR = 0)
# ============================================================
    #li    t1, 0x00
    #sb    t1, 0x10(t0)

li x8,8 #number of words in total

    # -------------------------------------
    # 7. Send String: "Ready\n"
    # -------------------------------------
    la    a1, msg_ready       # Load address of the string
    
print_loop:
    lb    a2, 0(a1)           # Load byte from string
    beqz  a2, handshake            # If byte is 0 (null terminator), finish         

    sb    a2, 0x00(t0)        # Write character to THR
    addi  a1, a1, 1           # Increment string pointer
    j     print_loop    
    
handshake:
li x10,4  #busrt count
li a1,5
print_loop_:           # Load byte from string
    beqz  a1, loop_            # If byte is 0 (null terminator), finish         
    sb    a1, 0x00(t0)        # Write character to THR
    addi  a1, a1, -1           # Increment string pointer
    j     print_loop_


loop_:    
li x6,4
li x31,0
li x30,0
loop:
    lb x7,0x0c(t0) # load the content of line status register (LSR)
    andi x7,x7,0x1 # check if atleast one fifo location is filled.
    beqz x7,loop   # start reading the receive buffer once the overrun occurs.
     
                
read:
    lbu a1,0(t0)
    sll a1,a1,x31
    add x30,x30,a1
    addi x31,x31,8
    addi x6,x6,-1
    beqz x6,sw_fw
    j loop
    
    
 sw_fw:        
    sw x30,0(t4)
    addi t4,t4,4
    
    addi x8,x8,-1
    beqz x8,execute_fw
    
    addi x10,x10,-1
    beqz x10,handshake #go for next handshake
    j loop_ 
    
    
execute_fw: 
jalr ra, t3, 0
j    done   
done:
    j done
    
.data
msg_ready:
    .string "READY\n"
