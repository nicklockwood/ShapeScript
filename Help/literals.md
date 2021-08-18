Literals
---

Literals are values that you type in your ShapeScript file. They could be numbers, text or something else. Literals can be passed as parameters to [options](options.md), [functions](functions.md) or [commands](commands.md), or used in [expressions](expressions.md). Here are some examples:

```swift
5 // an integer literal

37.2 // a floating-point literal

"hello" // a text literal

1 0 0 // a vector literal
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

---
[Index](index.md) | Next: [Expressions](expressions.md)
