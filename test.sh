#!/bin/bash

SRC=programs/unit_tests.asm

./run.sh "$SRC" |
perl -ne '
    print;
    if (/^[[:xdigit:]]{4} 3fff .* r14=([[:xdigit:]]{4})/) {
        if ($1 eq "0000") {
            print "SUCCESS\n";
            exit 0;
        } else {
            print "FAIL at $1\n";
            exit 1;
        }
    }
'
