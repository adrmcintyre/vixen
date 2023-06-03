#!/bin/bash

prog="${1:-programs/halt.asm}"

./asm.pl "$prog" || exit 1

iverilog -Wall \
    -s "top" \
    -o "out/simulation.vvp" \
    -y. harness.v || exit 1

vvp out/simulation.vvp -lxt2 || exit 1

#gtkwave test.lxt >& /dev/null &
#gtkwave view.gtkw >& /dev/null &


