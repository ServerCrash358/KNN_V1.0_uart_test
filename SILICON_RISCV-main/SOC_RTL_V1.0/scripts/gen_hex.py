# RISC-V RV32I instruction encoder for bootloader and firmware

def r_type(funct7, rs2, rs1, funct3, rd, opcode=0b0110011):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def i_type(imm, rs1, funct3, rd, opcode):
    imm = imm & 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def s_type(imm, rs2, rs1, funct3, opcode=0b0100011):
    imm = imm & 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | opcode

def b_type(imm, rs2, rs1, funct3, opcode=0b1100011):
    imm = imm & 0x1FFF
    b12 = (imm >> 12) & 1
    b11 = (imm >> 11) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode

def u_type(imm, rd, opcode):
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | opcode

def j_type(imm, rd, opcode=0b1101111):
    imm = imm & 0x1FFFFF
    b20 = (imm >> 20) & 1
    b19_12 = (imm >> 12) & 0xFF
    b11 = (imm >> 11) & 1
    b10_1 = (imm >> 1) & 0x3FF
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (rd << 7) | opcode

def to_signed(val, bits):
    if val < 0:
        val = (1 << bits) + val
    return val

# Register aliases
x0=0; ra=1; x1=1; x5=5; x6=6; x7=7; x10=10; x11=11; x12=12; x13=13
x28=28; x29=29; x30=30; x31=31

# ============================================================
# BOOTLOADER instructions
# ============================================================
boot = []

# UART config
boot.append(u_type(0x03000, x5, 0b0110111))   # 0x000: lui x5, 0x03000
boot.append(u_type(0x00001, x29, 0b0110111))   # 0x001: lui x29, 0x00001
boot.append(u_type(0x00001, x28, 0b0110111))   # 0x002: lui x28, 0x00001
boot.append(i_type(0x80, x0, 0b000, x6, 0b0010011))  # 0x003: addi x6, x0, 0x80
boot.append(s_type(3, x6, x5, 0b000))          # 0x004: sb x6, 3(x5)
boot.append(i_type(0x00, x0, 0b000, x6, 0b0010011))  # 0x005: addi x6, x0, 0
boot.append(s_type(1, x6, x5, 0b000))          # 0x006: sb x6, 1(x5)
boot.append(i_type(0x36, x0, 0b000, x6, 0b0010011))  # 0x007: addi x6, x0, 0x36
boot.append(s_type(0, x6, x5, 0b000))          # 0x008: sb x6, 0(x5)
boot.append(i_type(0x03, x0, 0b000, x6, 0b0010011))  # 0x009: addi x6, x0, 3
boot.append(s_type(3, x6, x5, 0b000))          # 0x00A: sb x6, 3(x5)
boot.append(i_type(0xC6, x0, 0b000, x6, 0b0010011))  # 0x00B: addi x6, x0, 0xC6
boot.append(s_type(2, x6, x5, 0b000))          # 0x00C: sb x6, 2(x5)
boot.append(i_type(8, x0, 0b000, x10, 0b0010011))    # 0x00D: addi x10, x0, 8

# Handshake: send bytes 1,2,3,4
boot.append(i_type(1, x0, 0b000, x6, 0b0010011))     # 0x00E: addi x6, x0, 1
boot.append(i_type(5, x0, 0b000, x7, 0b0010011))     # 0x00F: addi x7, x0, 5
boot.append(s_type(0, x6, x5, 0b000))                 # 0x010: sb x6, 0(x5)
boot.append(i_type(1, x6, 0b000, x6, 0b0010011))     # 0x011: addi x6, x6, 1
boot.append(b_type(to_signed(-8, 13), x6, x7, 0b101)) # 0x012: bge x7, x6, -8

# Receive loop: loop_ label at 0x013
boot.append(i_type(4, x0, 0b000, x6, 0b0010011))     # 0x013: addi x6, x0, 4
boot.append(i_type(0, x0, 0b000, x31, 0b0010011))     # 0x014: addi x31, x0, 0
boot.append(i_type(0, x0, 0b000, x30, 0b0010011))     # 0x015: addi x30, x0, 0

# poll: loop label at 0x016
boot.append(i_type(0x0C, x5, 0b000, x7, 0b0000011))   # 0x016: lb x7, 12(x5)
boot.append(i_type(0x01, x7, 0b111, x7, 0b0010011))   # 0x017: andi x7, x7, 1
boot.append(b_type(to_signed(-8, 13), x0, x7, 0b000))  # 0x018: beq x7, x0, -8

# read byte
boot.append(i_type(0, x5, 0b100, x11, 0b0000011))     # 0x019: lbu x11, 0(x5)
boot.append(r_type(0, x31, x11, 0b001, x11))           # 0x01A: sll x11, x11, x31
boot.append(r_type(0, x11, x30, 0b000, x30))           # 0x01B: add x30, x30, x11
boot.append(i_type(8, x31, 0b000, x31, 0b0010011))     # 0x01C: addi x31, x31, 8
boot.append(i_type(to_signed(-1, 12), x6, 0b000, x6, 0b0010011)) # 0x01D: addi x6, x6, -1
boot.append(b_type(to_signed(8, 13), x0, x6, 0b000))   # 0x01E: beq x6, x0, 8

# jal x0, back to loop at 0x016: offset = (0x016-0x01F)*4 = -36
boot.append(j_type(to_signed(-36, 21), x0))             # 0x01F: jal x0, -36

# sw_fw label at 0x020
boot.append(s_type(0, x30, x29, 0b010))                 # 0x020: sw x30, 0(x29)
boot.append(i_type(4, x29, 0b000, x29, 0b0010011))      # 0x021: addi x29, x29, 4
boot.append(i_type(to_signed(-1, 12), x10, 0b000, x10, 0b0010011)) # 0x022: addi x10, x10, -1
boot.append(b_type(to_signed(8, 13), x0, x10, 0b000))    # 0x023: beq x10, x0, 8

# jal x0, back to loop_ at 0x013: offset = (0x013-0x024)*4 = -68
boot.append(j_type(to_signed(-68, 21), x0))               # 0x024: jal x0, -68

# execute_fw label at 0x025
boot.append(i_type(0, x28, 0b000, ra, 0b1100111))         # 0x025: jalr x1, x28, 0
boot.append(j_type(to_signed(4, 21), x0))                  # 0x026: jal x0, 4

# done label at 0x027
boot.append(j_type(to_signed(0, 21), x0))                  # 0x027: jal x0, 0

print("=" * 60)
print("BOOTLOADER (sim_sram init at word address 0x000):")
print("=" * 60)
for i, instr in enumerate(boot):
    print(f"  0x{i:03X}: 32'h{instr:08X}")

# Verify against known bootrom values
known = {
    0x000: 0x030002B7,
    0x001: 0x00001EB7,
    0x002: 0x00001E37,
    0x003: 0x08000313,
    0x004: 0x006281A3,
    0x005: 0x00000313,
    0x006: 0x006280A3,
    0x007: 0x03600313,
    0x008: 0x00628023,
    0x009: 0x00300313,
    0x00A: 0x006281A3,
    0x00B: 0x0C600313,
    0x00C: 0x00628123,
    0x012: 0xFE63DCE3,
}
print()
print("Verification against known bootrom:")
all_ok = True
for addr, expected in known.items():
    actual = boot[addr]
    ok = actual == expected
    if not ok:
        all_ok = False
    status = "OK" if ok else f"MISMATCH (got 0x{actual:08X})"
    print(f"  0x{addr:03X}: expected 0x{expected:08X} -> {status}")
print(f"  Overall: {'ALL OK' if all_ok else 'ERRORS FOUND'}")

# ============================================================
# ADD 1+1 firmware
# ============================================================
fw = []
fw.append(i_type(1, x0, 0b000, x10, 0b0010011))    # addi x10, x0, 1
fw.append(i_type(1, x10, 0b000, x11, 0b0010011))   # addi x11, x10, 1
fw.append(u_type(0x05000, x12, 0b0110111))          # lui x12, 0x05000
fw.append(s_type(0, x11, x12, 0b010))               # sw x11, 0(x12)
fw.append(u_type(0x03000, x12, 0b0110111))          # lui x12, 0x03000
fw.append(i_type(0x30, x11, 0b000, x13, 0b0010011)) # addi x13, x11, 0x30
fw.append(s_type(0, x13, x12, 0b000))               # sb x13, 0(x12)
fw.append(i_type(0, ra, 0b000, x0, 0b1100111))      # jalr x0, x1, 0

print()
print("=" * 60)
print("ADD 1+1 FIRMWARE (loaded at 0x1000):")
print("=" * 60)
for i, instr in enumerate(fw):
    b = instr.to_bytes(4, 'little')
    print(f"  Word {i}: 0x{instr:08X}  Bytes(LE): {b[0]:02X} {b[1]:02X} {b[2]:02X} {b[3]:02X}")

# Print fw_array init
print()
print("fw_array initialization for testbench:")
idx = 0
for instr in fw:
    b = instr.to_bytes(4, 'little')
    for byte_val in b:
        print(f"  fw_array[{idx}] = 8'h{byte_val:02X};")
        idx += 1

print(f"\nTotal firmware bytes: {idx}")
print(f"Total firmware words: {len(fw)}")
