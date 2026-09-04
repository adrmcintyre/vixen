#!/bin/bash

(cd tests && mkdir -p tmp) || exit 1

if [ $# = 0 ]; then
    tests=(tests/*.lang)
else
    tests=("$@")
fi

for t in "${tests[@]}"; do
    # remove leading path and extract filename minux suffix
    base=$(basename -s .lang "$t")
    run=tests/tmp/"$base.run"
    want=tests/tmp/"$base.want"
    got=tests/tmp/"$base.got"

    # keep only lines starting ## or containing #!
    # then remove everything before #!
    # then remove possible trailing !
    # finally append a trailing newline
    sed -E '/^##|#!/!d;s/.*#!//;s/!$//;$a\'$'\n' "$t" > "$want"

    # expand ## to print the entire line
    sed -E 's/^##.*/print "&"/' "$t" > "$run"

    ./lang "$run" >& "$got"
    diff -u "$want" "$got"
done
