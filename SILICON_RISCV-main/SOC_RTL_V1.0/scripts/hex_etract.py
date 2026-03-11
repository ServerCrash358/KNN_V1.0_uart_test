import re

# Regex to find and capture the 8-digit hex instruction
# Pattern: [any_whitespace][address]:[any_whitespace][instruction_hex][any_whitespace][mnemonic]
instruction_regex = re.compile(r"^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s+.*$")

input_filename = "disassembly.dump"
output_filename = "instructions.txt"

instructions_found = 0

try:
    # Open the input file for reading and output file for writing
    with open(input_filename, 'r') as f_in, open(output_filename, 'w') as f_out:
        for line in f_in:
            # Try to match the regex pattern on the current line
            match = instruction_regex.match(line)
            
            # If a match is found (i.e., it's an instruction line)
            if match:
                # Get the captured group (the hex instruction)
                hex_instruction = match.group(1)
                
                # Write it to the output file with a comma and newline
                f_out.write(f"{hex_instruction},\n")
                instructions_found += 1

    print(f"✅ Success: Extracted {instructions_found} instructions.")
    print(f"Output saved to: {output_filename}")

except FileNotFoundError:
    print(f"❌ Error: Input file '{input_filename}' not found.")
    print("Please save your disassembly text to that file and try again.")