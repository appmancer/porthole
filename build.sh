#!/bin/bash
beebasm -i main.asm -do bf6502.ssd -title "BF6502" -boot PROGRAM -v
echo "Build complete! Output: bf6502.ssd"
