.text
li x27,0x01000000
li      t0, 4000      # loop counter = 4000

li x28,0x03000000
li x29,0x00002000



# ============================================================
# 1. Disable interrupts  (IER = 0)
# ============================================================
    #li    t1, 0x00
    #sb    t1, 0x04(t0)


# ============================================================
# 2. Enable Divisor Latch Access (DLAB=1)  LCR = 0x80
# ============================================================
    li    t1, 0x80
    sb    t1, 0x03(x28)


# ============================================================
# 3. Set baud divisor for 115200 @ 100 MHz
#     DLL = 0x36
#     DLM = 0x00
# ============================================================

    li    t1, 0x00
    sb    t1, 0x01(x28)              # DLM
    li    t1, 0x36
    sb    t1, 0x00(x28)              # DLL




# ============================================================
# 4. Set line for 8N1 (DLAB=0)   LCR = 0x03
# ============================================================
    li    t1, 0x03
    sb    t1, 0x03(x28)


# ============================================================
# 5. Enable FIFO, clear FIFOs  FCR = 0xC1
# ============================================================
    li    t1, 0xC6
    sb    t1, 0x02(x28)




loop:
    # --- loop body: put code here ---
    addi    t0, t0, -1    # decrement counter
    bne     t0, x0, loop
li x2,0x01000000
li x31,4
read_first_locations:
lw x3,0(x2)
sw x3,0(x29)
lw x3,0(x29)
sb x3,0(x28)
addi x2,x2,4
addi x29,x29,4
addi x31,x31,-1
bnez x31,read_first_locations

li x9,0
lui x9,0x1FF
li x8,0xFF0
add x9,x9,x8
add x10,x27,x9

li x31,4
read_last_words_4:
lw,x3,0(x10)
sw x3,0(x29)
lw x3,0(x29)
sb x3,0(x28)
addi x10,x10,4
addi x29,x29,4
addi x31,x31,-1
bnez x31,read_last_words_4


