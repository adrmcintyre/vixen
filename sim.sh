#!/bin/bash

PROGRAM="${1:-programs/halt.asm}"

if ! ./asm.pl "$PROGRAM" > out/asm.log; then
    cat out/asm.log
    exit 1
fi

if ! gcc -o ./out/sim ./sim.c >& out/gcc.log; then
    cat out/gcc.log
    exit 1
fi

./out/sim -A out/asm.log | tee out/sim.log
