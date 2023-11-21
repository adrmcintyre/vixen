#!/bin/bash

OUT="out/f16-test"
SRC="programs/f16"

if [ $# = 0 ]; then
    TESTS=(mul div add sub)
else
    TESTS=("$@")
fi

function run_test() {
    local op="$1"; shift
    local libs=(
        "$SRC/harness.asm"
        "$SRC/${op}_testdata.asm"
        "$SRC/internal.asm"
        "$SRC/${op}.asm"
        "$@"
    )
    local logs="$OUT/$op"

    rm -rf "$logs"
    mkdir -p "$logs"
    if ! ./asm.pl "${libs[@]}" > "$logs/asm.log"; then
        echo >&2 "..."
        tail >&2 "$logs/asm.log"
        exit 1
    fi

    ./out/sim --color |
        tee "$logs/color.log" | sed $'s/\e\[[^m]*m//g' |
        tee "$logs/plain.log" | grep 'ffff ....$' |
        tee "$logs/fail.log"
}

for t in "${TESTS[@]}"; do
    [ "$t" = mul ] && run_test mul 
    [ "$t" = div ] && run_test div 
    [ "$t" = add ] && run_test add programs/f16/sub.asm
    [ "$t" = sub ] && run_test sub programs/f16/add.asm
done

