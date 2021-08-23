Loops
---

To repeat an instruction (or sequence of instructions) you can use a `for` loop. The simplest form of the for loop takes a [numeric range](expressions.md#ranges), and a block of instructions inside braces. The following loop creates a circle of 5 points (you might use this inside a `path`):

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

---
[Index](index.md) | Next: [Blocks](blocks.md)
