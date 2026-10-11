# TODO

## Internals

Implement min_cap and/or no_shrink on arrays.

Escape strings in composite objects during printing.

Link discarded allocations for reuse.

Separate compile time and runtime heaps.
The compile team heap will descend from the top of memory, while the runtime
heap will ascend from end of bytecode. Strings, func, and class descriptors
should be embedded inside the bytecode.

Intern all literal strings.

## Arithmetic

Check for integer overflow on unary-, +, -, *, abs, int?
Add explicit // integer division operator?
Abort on integer /0, %0?

## Tests

Add tests compile time and run time errors.

## Errors

Make errors more informative.

## Classes

Ensure prop definitions are complete, i.e. disallow:

    ```
    class C
        some_ident      # missing '= value' - or maybe make this a required constructor arg?
        1+2             # random expression
    end
    ```
Implement class methods.


## Dictionaries

* del
* keys
* values

