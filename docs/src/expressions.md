Expressions
---

Rather than pre-calculating the sizes and positions of your shapes, you can get ShapeScript to compute the values for you using *expressions*.

Expressions are formed by combining [literal values](literals.md), [symbols](symbols.md) or [functions](functions.md) with *operators*.


## Operators

Operators are used in conjunction with individual values to perform calculations:

```swift
5 + 3 * 4
```

ShapeScript supports all the standard [infix](https://en.wikipedia.org/wiki/Infix_notation) arithmetic operators:

Symbol         | Name                  | Function
:------------- | :-------------------- | :--------------------------------------------------------------------
&plus;         | plus                  | Adds the left and right values
&dash;         | minus                 | Subtracts the right value from the left value
&ast;          | times                 | Multiplies the left value by the right value
&sol;          | divide                | Divides the left value by the right value
&percnt;       | modulo                | Remainder of dividing the left value by the right value

<br>

Unary + and - are also supported:

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

## Equality and Comparison

ShapeScript includes the following equality and comparison operators, which can be used in [conditional logic](control-flow.md#if-else):

Symbol         | Name                  | Function
:------------- | :-------------------- |:--------------------------------------
=              | equal                 | Compares two values and returns `true` if they are equal
<>             | not equal             | Compares two values and returns `false` if they are equal
<              | less than             | Returns `true` if the left value is less than the value on the right
<=             | less than or equal    | Returns `true` if the left value is less than or equal to the right
&gt;           | greater than          | Returns `true` if the left value is greater than the value on the right
&gt;=          | greater than or equal | Returns `true` if the left value is greater than or equal to the right

<br>

**Note:** You may have used other languages where `=` is written as `==`. This is generally because in such languages the `=` operator is used for assignment, and re-using the same symbol would cause ambiguity. This is not a problem in ShapeScript.

While these operators are typically used with numeric inputs, the *output* is a boolean value (`true` or `false`). These values are most commonly used in conjunction with with the `if/else` control flow statement. For example:

```swift
if rnd > 0.5 {
    print "heads"
} else {
    print "tails"
}
```

But they can also be assigned to a symbol and passed around:

```swift
define averageColor (color.red + color.green + color.blue) / 3
define isBrightColor averageColor >= 0.5
print isBrightColor // prints true or false
```

## Linear Algebra

As well as operating on individual numbers, some operators can be used with [vectors or tuples](literals.md#vectors-and-tuples). To multiply or divide a tuple of numbers by a scalar value you can use:

```swift
define numbers (1 2 3 -4)
print numbers * 2 // prints 2 4 6 -8
```

You can also multiply two tuples:

```swift
define left (1 2 3)
define right (1 -2 3)
print left * right // prints 1 -4 9
```

Note that is a simple member-wise multiplication of the numbers. For other types of vector multiplication such as the dot or cross product see the [functions section](functions.md#linear-algebra).

If the tuples have different lengths, the result will be truncated to the shorter of the two:

```swift
define left (1 2 3)
define right (1 -2)
print left * right // prints 1 -4
```

You can also add or subtract two lists of numbers together:

```swift
define left (1 2 3)
define right (1 -2 3)
print left + right // prints 2 0 6
```

Unlike with multiplication or division, adding or subtracting a shorter tuple from a longer one will preserve the length of the left side:

```swift
define left (1 2 3)
define right (1 -2)
print left + right // prints 2 0 3
```

Adding a longer tuple to a shorter one will not widen the result however:

```swift
define left (1 2 3)
define right (1 -2 3 4)
print left + right // prints 2 0 3
```

## Boolean Algebra

Along with the standard arithmetic operators, ShapeScript also has [boolean operators](https://en.wikipedia.org/wiki/Boolean_algebra) for implementing logical operations.

Not to be confused with the [boolean geometry](csg.md) functions for working with 3D solids, ShapeScript's boolean operators work with `true` or `false` values, and are predominantly used in conjunction with `if/else` control flow statements.

ShapeScript supports the common boolean operators:

Operator       | Function
:------------- | :--------------------
and            | Compares two values and returns `true` if they are both true
or             | Compares two values and returns `true` if either one is true
not            | Returns `false` if the expression to the right is true, and `true` if it's false

<br>

Unlike some languages, ShapeScript's boolean operators are implemented as keywords rather than symbols like `&&` or `||`, so control flow statements read more like sentences:

```swift
if a and b {
    print "both a and b were true"    
}
```

These can be combined into more complex expressions, and used in conjunction with parentheses for disambiguation:

```swift
if (not a) and (b or c) {
    print "a was false and either b or c were true"  
}
```

## Members

Compound values like [vectors and tuples](literals.md#vectors-and-tuples) and [objects](literals.md#objects) can be decomposed by using the *dot* operator to access individual components or *members*:

```swift
define vector 0.5 0.2 0.4
define yComponent vector.y
print yComponent 0.2
```

Like other operators, the dot operator can be used as part of a larger expression:

```swift
color 1 0.5 0.2
define averageColor (color.red + color.green + color.blue) / 3
print averageColor // prints 0.5667
```

For strings, you can use the `lines`, `words` and `characters` members:

```swift
define sentence "The quick brown fox"
for word in sentence {
    print word // prints each word on a new line
}
```

For [paths](paths.md) you can access the `bounds` and `points` members. For each point you can access the `position`, `isCurved` and `color`:

```swift
// Print the points in a circle
for point in circle.points {
    print "position: " point.position ", isCurved: " point.isCurved
}
```

For [meshes](meshes.md) you can access the `name`, `bounds` and `polygons` members:

```swift
print cube.bounds.size // prints 1 1 1
print cube.polygons.count // prints 6
```

For [polygons](meshes.md#polygons-and-points) you can get the `bounds` or `center`, or use `points` to access the individual vertices. For points you can access the `position` and `color`:

```swift
define triangle polygon {
    color red
    point 0 0
    color green
    point 1 0
    color blue
    point 1 1
}

// Print the vertex positions and colors
for point in triangle.points {
    print "position: " point.position ", color: " point.color
}
```

For more information about the members that can be accessed on various data types, see [structured data](literals.md#structured-data).


## Ranges

Another type of expression you can create is a *range* expression. This consists of two numeric values separated by a `to` keyword:

```swift
1 to 5
```

Ranges are mostly used in [for loops](control-flow.md#loops):

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

The step value for an existing range can be set or overridden later:

```swift
define loops 1 to 5 step 3

for i in loops {
    print i // prints 1, 4
}

for i in loops step 2 {
    print i // prints 1, 3, 5 
}
```

A negative `step` can be used to create a [backwards loop](control-flow.md#looping-backwards):

```swift
for i in 5 to 1 step -1 {
    print i // prints 5, 4, 3, 2, 1
}
```

---
[Index](index.md) | Next: [Functions](functions.md)
