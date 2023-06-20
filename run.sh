#!/bin/bash

FONT="out/font.bin"
if [ ! -e "$FONT" ]; then
    echo >&2 "$FONT does not exist - perhaps you need to run make"
    exit 1
fi

PROGRAM="${1:-programs/halt.asm}"

./asm.pl "$PROGRAM" || exit 1

iverilog -Wall \
    -D IVERILOG \
    -s "harness" \
    -o "./out/simulation.vvp" \
    -y. -y./video "./harness.v" || exit 1

vvp "./out/simulation.vvp" -lxt2 || exit 1

#gtkwave "./out/test.lxt" >& /dev/null &
