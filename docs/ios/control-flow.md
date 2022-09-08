Control Flow
---

## Loops

To repeat an instruction (or sequence of instructions) you can use a `for` loop. The simplest form of the for loop takes a [numeric range](expressions.md), and a block of instructions inside braces. The following loop creates a circle of 5 points (you might use this inside a `path`):

```swift
for 1 to 5 {
    point 0 1
    rotate 2 / 5
}
```

The range `1 to 5` is inclusive of both the start and end values. A range of `0 to 5` would therefore loop *6* times and not 5 as you might expect.

The loop range does not have to be a literal value, you can use a previously defined symbol or expression instead:

```swift
define count 5

for 1 to count {
    point 0 1
    rotate 2 / count
}
```

## Loop Index

If you have used similar loops in other programming languages, you might be wondering why we don't need to use an index variable of some kind to keep track of the loop iteration?

Symbols defined inside the `{ ... }` block will not persist between loops (see [scope](scope.md) for details), but changes to the world transform will, which is why the `rotate` command doesn't need to reference the index - its effect is cumulative.

If you *do* need to reference the index inside your loop for some reason, you can define a loop index symbol like this:

```swift
for i in 1 to count {
    point 0 i
}
```

This defines a [symbol](symbols.md) called `i` with the value of the current loop iteration. The `i` symbol only exists within the loop body itself and can't be referenced after the loop has ended.

**Note:** The index symbol does not need to be called `i`, it can be any valid symbol name that you choose.

If you want to loop in increments greater or less than 1, you can use the optional `step` property:

```swift
for i in 1 to 5 step 2 {
    print i // prints 1, 3, 5 
}

for i in 0 to 1 step 0.2 {
    print i // prints 0, 0.2, 0.4, 0.6, 1
}
```

If not specified, the `step` value defaults to 1.

## Looping Backwards

If the end value of a loop is less than the start value, the loop body will normally be skipped, but if you do wish to loop backwards you can achieve this by using a negative step value:

```swift
for i in 5 to 1 step -1 {
    print i // prints 5, 4, 3, 2, 1
}
```

## Looping Over Values

As well as looping over a numeric range, you can also loop over a tuple of values:

```swift
define values 1 5 7 9

for i in values {
    print i // prints 1 5 7 9
}
```

The values can be non-numeric, or even a mix of different types:

```swift
define values "Mambo" "No." 5

for i in values {
    print i // prints Mambo No. 5
}
```

**Note:** To use a list of values directly in the loop definition, they must be placed in parentheses:

```swift
for i in ("parentheses" "are" "required") {
    print i
}
```

## If-Else

Sometimes instead of repeating an action multiple times you need to perform it just once, but conditionally, based on some programmatic criteria. For example, your model might have multiple configurations that you can switch between by setting constants at the top of the file.

To execute code conditionally, you can use an `if` statement:

```swift
define showCube true

if showCube {
    cube   
}
```

The `showCube` constant here is a [boolean](https://en.wikipedia.org/wiki/Boolean_data_type) that can have the value `true` or `false`. The condition for an `if` statement must always be a boolean expression. The body of the `if` statement will only be executed if the condition is true.

To perform an alternative action for when the condition is false, you can add an `else` clause:

```swift
if showCube {
    cube   
} else {
    sphere   
}
```

You can chain multiple conditional statements using the `else if` construct:

```swift
if showCube {
    cube   
} else if showSphere {
    sphere   
} else if showCone {
    cone
} else {
    print "Nothing to see here!"   
}
```

## Conditional Defines

Something you might want to do with an `if` statement is to conditionally define a constant value, for example:

```swift
define highlighted true

if highlighted {
    define cubeColor red
} else {
    define cubeColor white  
}

cube cubeColor
```

Unfortunately this won't work, due to the [scope](scope.md) rules. The `cubeColor` symbol is only defined inside the `if` statement blocks themselves, and can't be accessed outside. So how can you set the value of `cubeColor` conditionally?

The solution is to move the `if` statement *inside* the `define` itself, like this:

```swift
define highlighted true

define cubeColor {
    if highlighted {
        red
    } else {
        white  
    }
}

cube { color cubeColor }
```

---
[Index](index.md) | Next: [Blocks](blocks.md)
