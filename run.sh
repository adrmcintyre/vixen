#!/bin/bash

prog="${1:-programs/test.vx}"

(egrep '^[0-9a-f][0-9a-f]*  *' "$prog" | sed 's/^[0-9a-f]* //' | cut -b1-2; yes ff) | head -32768 > mem0.hex
(egrep '^[0-9a-f][0-9a-f]*  *' "$prog" | sed 's/^[0-9a-f]* //' | cut -b3-4; yes ff) | head -32768 > mem1.hex

iverilog -Wall \
    -s "top" \
    -o "output" \
    "top.v" || exit 1

vvp output -lxt2 || exit 1

#gtkwave test.lxt >& /dev/null &
#gtkwave view.gtkw >& /dev/null &


