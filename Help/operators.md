Operators
---

Operators are used in conjunction with values to form mathematical expressions:

```swift
5 + 3 * 4
```

Currently, ShapeScript supports only basic math operators such as +, -, * and /, and the values used with them must be numbers. Unary + and - are also supported:

```swift
-5 +7
```

Operator precedence follows the standard [BODMAS](https://en.wikipedia.org/wiki/Order_of_operations#Mnemonics) convention, and you can use parentheses to override the order of evaluation:

```swift
(5 + 3) * 4
```

Because spaces are used as delimiters in vector arguments, you need to take care with the spacing around operators to avoid ambiguity. Specifically, unary + and - must not have a space after them, and ordinary infix operators should have balanced space around them.

For example, these expressions would both evaluate to a single number with the value 4:

```swift
5 - 1
5-1
```

Whereas this expression would be interpreted as a 2D vector of 5 and -1:

```swift
5 -1
```

There are currently no vector or matrix math operators such as dot product or vector addition, but these are mostly not needed in practice due to the [relative transform](transforms.md#relative-transforms) commands.

---
[Index](index.md) | Next: [Symbols](symbols.md)
