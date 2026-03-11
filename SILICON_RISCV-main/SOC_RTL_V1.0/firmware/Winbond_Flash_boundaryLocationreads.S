.text
li x27,0x01000000
li      t0, 4000      # loop counter = 4000
loop:
    # --- loop body: put code here ---
    addi    t0, t0, -1    # decrement counter
    bne     t0, x0, loop
li x2,0x01000000
li x7, 0x03000000
li x31,4
read_first_locations:
lw x3,0(x2)
sw x3,0(x7)
addi x2,x2,4
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
sw x3,0(x7)
addi x10,x10,4
addi x31,x31,-1
bnez x31,read_last_words_4


