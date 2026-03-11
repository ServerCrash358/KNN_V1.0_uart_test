.text
li      t0, 4000      # loop counter = 4000
loop:
    # --- loop body: put code here ---
    addi    t0, t0, -1    # decrement counter
    bne     t0, x0, loop
li x2,0x01000000
li x7, 0x03000000
lw x3,0(x2)
sw x3,0(x7)
lw x3,4(x2)
sw x3,0(x7)

