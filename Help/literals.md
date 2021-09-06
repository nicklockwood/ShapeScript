Literals
---

Literals are values that you type in your ShapeScript file. They could be numbers, text or something else. Literals can be passed as parameters to [options](options.md), [functions](functions.md) or [commands](commands.md), or used in [expressions](expressions.md). Here are some examples:

```swift
5 // an integer literal

37.2 // a floating-point literal

"hello" // a text literal

1 0 0 // a vector literal

#FF0000 // a hex color literal
```

Text literals are delimited by double quotes (`"`) to prevent ambiguity if the text matches a keyword or [symbol](symbols.md), or contains spaces or other punctuation. 

Vector literals are just a sequence of numbers separated by spaces. They are often used to represent positions, colors, sizes and rotations.

## Escaping

Because text literals use `"` as delimiters, if you want to use a double quote *inside* the text itself then it must be *escaped* using a backslash (`\`) character:

```swift
"hello \"Bob\" (if that's your real name)"
```

A line containing a text literal without a closing `"` is treated as an error, so if you need to include line-breaks in your text then these must also be escaped. Use the escape sequence `\n` (short for "new line") to indicate a line-break:

```swift
"first line\nsecond line"
```

Because `\` is used as the escape character, it must also be escaped if you want it to appear literally in the text. Use a double `\\` in this case (there is no need to escape forward slashes (`/`) however):

```swift
"back slash: \\"
"forward slash: /"
```

## Vectors and Tuples

A sequence of values separated by spaces defines a vector or [tuple](https://en.wikipedia.org/wiki/Tuple). Many [commands](https://github.com/nicklockwood/ShapeScript/blob/develop/Help/commands.md) in ShapeScript accept a vector argument, and you can pass a vector literal to these commands directly:

```swift
translate 1 0 0
```

But you can also [define](symbols.md) a vector value to use later:

```swift
define size 1 0 0
```

A vector defined in this way doesn't have an explicit type - it's just a sequence of numbers. We might guess from the name "size" that it will be used to set the size of something, but there's nothing preventing you from using it as, say, a [color](materials.md#color) value:

```swift
define size 1 0 0
color size // sets color to red
```

Untyped vectors like this are called *tuples*. Tuples can be comprised of any type of value, or a mix of different types, including other tuples:

```swift
define size 1 2 3
define myTuple2 "hello" 5.3 size
```

## Structured Data

As well as simple values like numbers and strings, it can sometimes be useful to group together sets of related data. Tuples can be nested arbitrarily, in order to create complex data structures:

```swift
define matrix (1 2 3) (4 5 6) (7 8 9)
```

Parentheses are used here to indicate that this is a tuple of three nested tuples, and not just a single tuple of nine numbers. To make this more readable, you can split the data over multiple lines inside outer parentheses, and even use [comments](comments.md) if you wish:

```swift
define matrix (
    (1 2 3) // position
    (4 5 6) // scale
    (7 8 9) // orientation
)
```

**Note:** The line breaks have no semantic meaning here, they only serve to make the code more readable. Only the parentheses are relevant in determining the grouping.

Since no built-in commands in ShapeScript consume structured data like this, you need a way to access individual elements. You can do this in two ways:

To extract individual values from a tuple, you can use [member syntax](expressions.md#members). If the tuple is shaped like a vector, size or color then you can use the `x`/`y`/`z` or `red`/`green`/`blue`/`alpha` members:

```swift
define pos 1 2 0
print pos.y // 2

define size 3 4 5
print size.depth // 5

define col 1 0 0
print col.red // 1
```

For more abstract data, you can use the ordinal members (`first`, `second`, `third`, etc.) to access members by index:

```swift
define data (
    "cube" // name
    (1 2 3) // position
    #ff0000 // color
)

print data.first // name
print data.second // position
print data.third // color
```

Member expressions can be chained, so something like this will also work:

```swift
print matrix.second.x // x component of the position
```

For list-like data, you can use a [for loop](loops.md#looping-over-values) to loop over the top-level values:

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

---
[Index](index.md) | Next: [Expressions](expressions.md)
