Comments
---

Any content that follows a `//` (double slash) is treated as a comment. Comments can appear at the start of a line, or at the end. The comment terminates at the next line-break.

Comments can be used to document individual lines of code, or whole blocks. For example:

```swift
color 1 0 0 // red

// this code draws a triangle
fill {
    path {
        for 0 to 3 {
            point 0 1
            rotate 2 / 3
        }
    }
}
```

Comments are also useful for temporarily disabling a block of code when debugging a model. Some editors (such as Xcode) allow you to comment or uncomment multiple lines of code at once by making a multi-line selection and then pressing **Cmd-/** on the keyboard.

---
[Index](index.md) | Next: [Literals](literals.md)
