#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
BOARD=$1
APP_NAME="blinky"

if [ -z "$BOARD" ]; then
    echo "Error: Target board required (e.g., ./build.sh icesugar_nano)"
    exit 1
fi

OUTPUT_PREFIX="soc_${BOARD}"

case $BOARD in
    icesugar_nano)
        FPGA_TYPE="--lp1k"
        FPGA_PKG="cm36"
        ;;
    *)
        echo "Error: Unrecognized board ($BOARD)"
        exit 1
        ;;
esac

echo "--- Building for $BOARD | App: $APP_NAME ---"

mkdir -p build
rm -f build/*

# --- 2. SOFTWARE COMPILATION ---
echo "[1/4] Compiling C source..."
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -Os -ffreestanding -nostdlib \
    -T software/linker.ld software/start.S software/*.c -o build/${APP_NAME}.elf -lgcc

echo "[2/4] Generating RAM init file..."
riscv64-unknown-elf-objcopy -O binary build/${APP_NAME}.elf build/${APP_NAME}.bin

# Convert raw binary to 32-bit Little Endian hex text for Verilog BRAM initialization ($readmemh)
python3 -c "
import sys
with open('build/${APP_NAME}.bin', 'rb') as f:
    while chunk := f.read(4):
        chunk = chunk.ljust(4, b'\x00')
        print(f\"{int.from_bytes(chunk, 'little'):08x}\")
" > build/${APP_NAME}_ram.txt

# --- 3. HARDWARE SYNTHESIS ---
echo "[3/4] Synthesizing hardware (Yosys)..."

shopt -s nullglob
SRC_FILES=(boards/soc_pkg.sv cpu/*.v cpu/*.sv boards/$BOARD/*.sv)
shopt -u nullglob

if [ ${#SRC_FILES[@]} -eq 0 ]; then
    echo "Error: No source files found."
    exit 1
fi

echo " -> Translating SystemVerilog to pure Verilog with sv2v..."
sv2v "${SRC_FILES[@]}" > build/${OUTPUT_PREFIX}.v

yosys -q -p "read_verilog build/${OUTPUT_PREFIX}.v; synth_ice40 -top top -json build/${OUTPUT_PREFIX}.json"

# --- 4. PLACE & ROUTE ---
echo "[4/4] Place & Route and Bitstream..."
nextpnr-ice40 -q $FPGA_TYPE --package $FPGA_PKG \
    --pcf boards/$BOARD/*.pcf \
    --json build/${OUTPUT_PREFIX}.json \
    --asc build/${OUTPUT_PREFIX}.asc

icepack build/${OUTPUT_PREFIX}.asc build/${OUTPUT_PREFIX}.bin

echo "Success! Bitstream: build/${OUTPUT_PREFIX}.bin"