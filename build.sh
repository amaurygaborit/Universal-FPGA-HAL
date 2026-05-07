#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ==========================================
# 1. BUILD CONFIGURATION & VERIFICATION
# ==========================================
BOARD=$1
APP_NAME="blinky"

if [ -z "$BOARD" ]; then
    echo "Error: Target board must be specified."
    echo "Usage: ./build.sh <board_name> (e.g., ./build.sh icesugar_nano)"
    exit 1
fi

OUTPUT_PREFIX="soc_${BOARD}"

# Define hardware parameters based on the selected board
case $BOARD in
    icesugar_nano)
        FPGA_TYPE="--lp1k"
        FPGA_PKG="cm36"
        ;;
    *)
        echo "Error: Unrecognized board specified ($BOARD)."
        exit 1
        ;;
esac

echo "--- Starting build process for board: $BOARD | App: $APP_NAME ---"

# Clean and prepare the build directory
mkdir -p build
rm -f build/*

# ==========================================
# 2. SOFTWARE COMPILATION (C Bare-metal)
# ==========================================
echo "[1/5] Compiling C source code (Bare-metal RISC-V)..."

# GCC Flags explanation:
# -march=rv32i : Base integer instruction set only
# -mabi=ilp32  : Standard 32-bit integer ABI
# -Os          : Optimize for size
# -ffreestanding -nostdlib : Do not use standard C library or startup files
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -Os -ffreestanding -nostdlib \
    -T software/linker.ld software/start.S software/*.c -o build/${APP_NAME}.elf

echo "[2/5] Generating memory initialization file (${APP_NAME}_ram.txt)..."

# Extract raw machine code
riscv64-unknown-elf-objcopy -O binary build/${APP_NAME}.elf build/${APP_NAME}.bin

# Convert raw binary to 32-bit Little Endian hexadecimal text format for Verilog $readmemh
python3 -c "
import sys
with open('build/${APP_NAME}.bin', 'rb') as f:
    while chunk := f.read(4):
        # Pad with null bytes if the chunk is less than 4 bytes
        chunk = chunk.ljust(4, b'\x00')
        print(f\"{int.from_bytes(chunk, 'little'):08x}\")
" > build/${APP_NAME}_ram.txt

# ==========================================
# 3. HARDWARE SYNTHESIS
# ==========================================
echo "[3/5] Translating SystemVerilog to Verilog-2005 (sv2v)..."

# Enable nullglob so unmatched patterns expand to nothing instead of the literal string
shopt -s nullglob

# Gather all potential source files into an array
SRC_FILES=(cpu/*.v cpu/*.sv boards/$BOARD/*.sv)

# Disable nullglob to return to standard bash behavior
shopt -u nullglob

# Verify that we actually found some source files
if [ ${#SRC_FILES[@]} -eq 0 ]; then
    echo "Error: No Verilog (.v) or SystemVerilog (.sv) files found in cpu/ or boards/$BOARD/."
    exit 1
fi

# Combine the universal CPU core and the board-specific top module
sv2v "${SRC_FILES[@]}" > build/${OUTPUT_PREFIX}.v

echo "[4/5] Synthesizing hardware (Yosys)..."

# Yosys reads the compiled Verilog and will natively pull the initialized RAM text file during synthesis
yosys -q -p "read_verilog build/${OUTPUT_PREFIX}.v; synth_ice40 -top top -json build/${OUTPUT_PREFIX}.json"

# ==========================================
# 4. PLACE AND ROUTE (PNR) & BITSTREAM
# ==========================================
echo "[5/5] Running Place-and-Route and generating Bitstream (NextPNR & Icepack)..."

nextpnr-ice40 -q $FPGA_TYPE --package $FPGA_PKG \
    --pcf boards/$BOARD/*.pcf \
    --json build/${OUTPUT_PREFIX}.json \
    --asc build/${OUTPUT_PREFIX}.asc

icepack build/${OUTPUT_PREFIX}.asc build/${OUTPUT_PREFIX}.bin

echo "BUILD SUCCESSFUL! Bitstream generated at: build/${OUTPUT_PREFIX}.bin"