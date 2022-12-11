Comments
---

Any content that follows a `//` (double slash) is treated as a comment. Comments can appear at the start of a line, or at the end. The comment terminates at the next line-break.

Comments can be used to document individual lines of code, or whole blocks. For example:

```swift
color 1 0 0 // red

// this code draws a triangle
fill path {
    for 0 to 3 {
        point 0 1
        rotate 2 / 3
    }
}
```

Comments are also useful for temporarily disabling a block of code when debugging a model. Some editors (such as Xcode) allow you to comment or uncomment multiple lines of code at once by making a multi-line selection and then pressing **Cmd-/** on the keyboard.

## Block Comments

Another way to disable a large chunk of code at once is to use a *block comment*. Block comments begin with `/*` and end with `*/`. Anything between these delimiters is considered part of the comment, even if they span multiple lines:

```swift
/*
// this code is disabled
fill path {
    for 0 to 3 {
        point 0 1
        rotate 2 / 3
    }
}
*/
```

Block comments can also be useful if you want to place a comment in the middle of a line, for example:

```swift
define a(b c d) {
    b /* + c */ + d
}
```

Here we've excluded the `c` parameter from the result, however the code both before and after the comment is unaffected.

## Nested Comments

Unlike some other languages, ShapeScript allows block comments to be nested inside each other. This is useful if you want to comment out some code that already contains comments:

```swift
/*
define foo {
    option bar 3
    /* option baz 5 */
    
    // return bar
    print bar
}
/*
```

---
[Index](index.md) | Next: [Literals](literals.md)
