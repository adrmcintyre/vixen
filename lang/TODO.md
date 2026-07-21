# TODO

## Misc

Chained indexing.
Escape strings in composite objects during printing.

## Ref-counted heap objects

Ref counting of strings, arrays, dicts?

## Internals

Use dicts internally for string and identifier hash tables.

## Dictionaries
### Other operations:
* del
* . operator ???

#### Allow numbers as dict keys

    Dict literal syntax:     d = {a:3, b:4}
    Dict constructor syntax: d = dict("a", 3, "b", 4)
    Dict . lookup:           e = d.a
    Dict [] lookup:          e = d["a"]

How to represent missing element: `None` ?

## Objects

* An object is just a dict with an attached method table.
* No inheritance
* No special constructors

### Declaration
    class Point

    # "class" method
    func Point.fromArray(xy)
        return Point{x:xy[0], y:xy[1]}
    end

    # instance methods
    func Point.add(self, p2)
        # direct construction
        return Point{x: self.x+p2.x, y: self.y+p2.y}
    end

    func Point.sub(self, p2)
        # default construction
        p = Point{}
        # set instance vars one by one
        p.x = self.x - p2.x
        p.y = self.y - p2.y
        return p
    end

### Construction
    p = Point{x:30, y:40}
    p = Point.fromArray([30, 40])

### Method invocation
    p = Point{x:30, y:40}
    q = Point{x:10, y:10}
    r = p.add(q)            # implicit self arg

    r = Point.add(p, q)     # explicit self arg

### Prevent these cases...?

    # construct a partially initialised Point
    p = Point{x:99}

    # construct an invalid Point
    p = Point{z:"kwanza", foo:True}

