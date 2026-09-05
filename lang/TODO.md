# TODO

## Internals

Implement min_cap and/or no_shrink on arrays.

Escape strings in composite objects during printing.

Ref counting of strings, arrays, dicts?

Link discarded allocations for reuse.

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
* iteration
    ```
        for k, v in d
            ...
        end
    ```

## Arrays

* iteration
    ```
    for i, e in a
        ...
    end
    ```