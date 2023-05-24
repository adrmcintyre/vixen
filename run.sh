#!/bin/bash

prog="${1:-programs/test.vx}"

./asm.pl "$prog" || exit 1

iverilog -Wall \
    -s "top" \
    -o "simulation.vvp" \
    *.v || exit 1

vvp simulation.vvp -lxt2 || exit 1

#gtkwave test.lxt >& /dev/null &
#gtkwave view.gtkw >& /dev/null &


