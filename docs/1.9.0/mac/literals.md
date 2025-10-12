Literals
---

Literals are values that you type in your ShapeScript file. They could be numbers, text or something else. Literals can be passed as parameters to [options](options.md), [functions](functions.md) or [commands](commands.md), or used in [expressions](expressions.md). Here are some examples:

```swift
5 // an integer literal

37.2 // a decimal literal

false // a boolean literal

"hello" // a string literal

1 0 0 // a vector literal

#FF0000 // a hex color literal
```

## Strings

Strings are how human-readable text is represented in ShapeScript. These are used for a variety of purposes, including specifying file names for [imports](import.md) or [textures](materials.md#texture), [logging](debugging.md#logging) debug information to the console, or even rendering 3D text.

String literals are delimited by double quotes (`"`) to prevent ambiguity if the text matches a keyword or [symbol](symbols.md), or contains spaces or other punctuation. If you want to use a double quote *inside* the text itself then it must be *escaped* using a backslash (`\`) character:

```swift
"hello \"Bob\" (if that's your real name)"
```

A line containing a string literal without a closing `"` is treated as an error, so if you need to include line-breaks in your string then these must also be escaped. Use the escape sequence `\n` (short for "new line") to indicate a line-break:

```swift
"first line\nsecond line"
```

Because `\` is used as the escape character, it must also be escaped if you want it to appear literally in the string. Use a double `\\` in this case (there is no need to escape forward slashes (`/`) however):

```swift
"back slash: \\"
"forward slash: /"
```

## Vectors and Tuples

A sequence of values separated by spaces defines a [tuple](https://en.wikipedia.org/wiki/Tuple). A tuple of numeric values is also known as a *vector*.

Vectors are used in ShapeScript to represent positions, colors, sizes and rotations. Many [commands](https://github.com/nicklockwood/ShapeScript/blob/develop/Help/commands.md) in ShapeScript accept a vector argument, and you can pass a tuple to these commands directly:

```swift
translate 1 0 0
```

You can also [define](symbols.md) a tuple value to use later:

```swift
define size 1 1 0.5
```

A tuple defined in this way doesn't know if it's going to be used as a vector - it's just a sequence of numbers. We might guess from the name "size" that it will be used to set the size of something, but there's nothing preventing you from using it as, say, a [color](materials.md#color) value:

```swift
define size 1 1 0.5
color size // sets color to yellow
```

Tuples are't limited to numbers. They can be comprised of any type of value (including other tuples), or a mix of different types:

```swift
define size 1 2 3
define myTuple2 "hello" 5.3 size
```

Tuple values can be accessed by index using [ordinal members](expressions.md#members) or [subscripting](expressions.md#subscripting):

```swift
define size 1 2 3

print size.second // prints 2
print size[0] // prints 1
```

To check if a tuple contains a particular value, you can use the `in` operator:

```swift
define values 1 2 3

if 2 in values {
    print "values includes the number 2"
}
```

You can also enumerate the values in a tuple using a [for loop](control-flow.md#looping-over-values):

```swift
define values 1 2 3

for value in values {
    print value // prints 1 2 3
}
```

## Structured Data

As well as simple values like numbers and text, it can sometimes be useful to group together sets of related data. Tuples can be nested arbitrarily to create complex data structures:

```swift
define matrix (1 2 3) (4 5 6) (7 8 9)
```

Parentheses are used here to indicate that this is a tuple of three nested tuples, and not a single tuple of nine numbers. To make this more readable, you can wrap the data over multiple lines inside outer parentheses, and even use [comments](comments.md) if you wish:

```swift
define matrix (
    (1 2 3) // position
    (4 5 6) // scale
    (7 8 9) // orientation
)
```

**Note:** The line breaks have no semantic meaning here, they only serve to make the code more readable. Only the parentheses are used to determine the grouping.

Since no built-in commands in ShapeScript consume structured data like this, you need a way to access individual elements. You can do this in two ways:

To extract individual values from a tuple, you can use [member syntax](expressions.md#members). If the tuple is numeric and shaped like a vector, size, rotation or color then you can use the `x`/`y`/`z`, `width`/`height`/`depth`, `roll`/`yaw`/`pitch` or `red`/`green`/`blue`/`alpha` members respectively:

```swift
define pos 1 2
print pos.x // prints 1
print pos.y // prints 2
print pos.z // prints 0

define size 3 4 5
print size.width // prints 3
print size.height // prints 4
print size.depth // prints 5

define rotation 0.5 0.25 0
print rotation.roll // prints 0.5
print rotation.yaw // prints 0.25
print rotation.pitch // prints 0

define col 1 0 0
print col.red // prints 1
print col.green // prints 0
print col.blue // prints 0
print col.alpha // prints 1
```

For more abstract data, you can use the ordinal members (`first`, `second`, `third`, ... `last`) to access members by index:

```swift
define data (
    "cube" // name
    (1 2 3) // position
    #ff0000 // color
)

print data.count // prints 3
print data.first // name
print data.second // position
print data.last // color
```

Member expressions can be chained, so something like this will also work:

```swift
print data.second.x // x component of the position
```

You can split up lists of data using the `allButFirst` and `allButLast` members:

```swift
define data (1 2 3 4 5)

print data.allButFirst // prints 2 3 4 5
print data.allButLast // prints 1 2 3 4
```

For list-like data, you can use a [for loop](control-flow.md#looping-over-values) to loop over the top-level values:

```swift
define positions (
    (1 1 2)
    (2 1 2)
    (3 1 2)
)

for p in positions {
    cube {
        position p 
    }
}
```

You can even use nested loops to access sub-elements:

```swift
define matrix (
    (1 2 3)
    (4 5 6)
    (7 8 9)
)

for row in matrix {
    for column in row {
        print column // prints 1 to 9
    }
}
```

You can also access elements using a computed index via [subscripting](expressions.md#subscripting):

```swift
print matrix[0][2] // prints 3 (first row, third column)
```

**Note:** There is no requirement that rows in such a structure are the same type or length:

```swift
define data (
    (1 2 3)
    (10) // single element
    () // empty tuple
    ("hello" "world") // non-numeric
)

for row in data {
    for element in row {
        print element // prints 1, 2, 3, 10, "hello", "world"
    }
}
```

## Objects

For more complex [structured data](#structured-data) you can use the `object` command to create an object with arbitrary, named members:

```swift
define data object {
    type "box"
    width 5
    height 10
    depth 15
}
```

To access the members of an object you can either use the [dot operator](expressions.md#members) or [subscripting](expressions.md#subscripting):

```swift
print data.height // prints 10
print data["height"] // also prints 10
```

Objects can be nested inside each other:

```swift
define data object {
    type "box"
    position 1 2 0
    dimensions object {
        width 5
        height 10
        depth 15
    }
}

print data.dimensions.height // prints 10
print data["dimensions"]["height"] // also prints 10
```

Attempting to access a non-existent member of an object will cause an error. To check if an object contains a particular member before you try to access it, you can use the `in` operator:

```swift
define axes object {
    x (1 0 0)
    y (0 1 0)
    z (0 0 1)
}

if "x" in axes {
    print "axes object contains an x component"
}
```

To enumerate all the members of an object, you can use a [for loop](control-flow.md#looping-over-values). Each member is returned as a tuple of the key (member name) and value:

```swift
for row in data {
    print "key: " row.first ", value: " row.second
}
```

**Note:** object members are *unordered*, meaning that the order in which they are defined has no special significance. When looping through members of an object, the order will be alphabetical rather than reflecting the order in which the members were defined.

---
[Index](index.md) | Next: [Symbols](symbols.md)
