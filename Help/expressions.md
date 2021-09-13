Expressions
---

Rather than pre-calculating the sizes and positions of your shapes, you can get ShapeScript to compute the values for you using *expressions*.

Expressions are formed by combining [literal values](literals.md), [symbols](symbols.md) or [functions](functions.md) with *operators*.


## Operators

Operators are used in conjunction with individual values to perform calculations:

```swift
5 + 3 * 4
```

ShapeScript supports common [infix](https://en.wikipedia.org/wiki/Infix_notation) math operators such as +, -, * and /. Unary + and - are also supported:

```swift
-5 * +7
```

Operator precedence follows the standard [BODMAS](https://en.wikipedia.org/wiki/Order_of_operations#Mnemonics) convention, and you can use parentheses to override the order of evaluation:

```swift
(5 + 3) * 4
```

Because spaces are used as delimiters in [vector literals](literals.md#vectors-and-tuples), you need to take care with the spacing around operators to avoid ambiguity. Specifically, unary + and - must not have a space after them, and ordinary infix operators should have balanced space around them.

For example, these expressions would both evaluate to a single number with the value 4:

```swift
5 - 1
5-1
```

Whereas this expression would be interpreted as a 2D vector of 5 and -1:

```swift
5 -1
```


## Members

There are currently no vector or matrix math operators such as dot product or vector addition, but these are mostly not needed in practice due to the [relative transform](transforms.md#relative-transforms) commands.

It is however possible to use vector, size, rotation or [color](materials.md#color) values in expressions by using the *dot* operator to access individual components:

```swift
define vector 0.5 0.2 0.4
define yComponent vector.y
print yComponent 0.2
```

Like other operators, the dot operator can be used as part of a larger expression:

```swift
define color 1 0.5 0.2
define averageColor (color.red + color.green + color.blue) / 3
print averageColor // 0.5667
```

For more information about the members that can be accessed on various data types, see [structured data](literals.md#structured-data).


## Ranges

Another type of expression you can create is a *range* expression. This consists of two numeric values separated by a `to` keyword:

```swift
1 to 5
```

Ranges are mostly used in [for loops](loops.md):

```swift
for i in 1 to 5 {
    print i   
}
```

But they can also be assigned to a [symbol](symbols.md) using the `define` command, and then used later:

```swift
define loops 1 to 5

for i in loops {
    print i // prints 1, 2, 3, 4, 5
}
```

**Note:** Ranges are inclusive of both the start and end values, so a loop from `0 to 5` would loop *6* times and not 5 as you might expect.

Range values can be fractional and/or negative:

```swift
for i in 0.2 to 2.2 {
    print i // prints 0.2, 1.2, 2.2
}

for i in -3 to -1 {
    print i // prints -3, -2, -1
}
```

Ranges may also include an optional `step` value to control how the range will be enumerated:

```swift
for i in 1 to 5 step 2 {
    print i // prints 1, 3, 5 
}

for i in 0 to 1 step 0.2 {
    print i // prints 0, 0.2, 0.4, 0.6, 1
}
```

A negative `step` can be used to create a [backwards loop](loops.md#looping-backwards):

```swift
for i in 5 to 1 step -1 {
    print i // prints 5, 4, 3, 2, 1
}
```

---
[Index](index.md) | Next: [Functions](functions.md)
