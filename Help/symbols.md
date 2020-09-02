Symbols
---

A symbol is a named value (sometimes referred to as a *constant*) that can be used in an expression in place of a [literal](literals.md) value.

ShapeScript includes several built-in symbols such as `detail` (the current level of detail), or `pi` (the mathematical constant used to compute angles), but you can also define your own symbols using the `define` command:

```swift
define sides 5
define red 1 0 0
```

Symbol names consist of a letter followed by zero or more letters or numbers. Symbols cannot begin with a number, and spaces or punctuation are not allowed. Symbols are case-sensitive, and by convention should begin with a lowercase letter. For multi-word symbols, the recommended convention is to capitalize the first letter of each new word (known as *camelCase* because the capital letters form "humps" in the back of the word):

```swift
define numberOfSides 7
```

The value assigned to a symbol can be a literal or an expression. Once defined, a symbol can be used anywhere in place of a literal value, such as inside an expression, or as a command parameter. Symbols can also be used in the definition of other symbols:

```swift
define three 3
define two 2
define five three + two
```

Symbols help to make your ShapeScript file more readable by assigning meaningful names to otherwise inscrutable literal values. They also make the script easier to modify and maintain by avoiding duplication of literal values throughout the code.

Existing symbols can redefined by calling `define` again with the same name. If a symbol is defined inside a `{ ... }` block then it will be [scoped](scope.md) to the code inside that block (meaning that it cannot be used after the closing `}`):

```swift
for i in 1 to 5 {
    define foo i // define symbol foo with the current loop index value
}
// foo is undefined here
```

Symbols can be *shadowed*, meaning that a symbol defined in an outer scope can be redefined inside an inner scope, but the symbol will revert to its original definition when the scope ends. It is currently only possible to create *constants*, you cannot create *variables* (symbols whose value can be changed later):

```swift
define foo 1
for i in 1 to 5 {
    define foo i // redefine foo with the current loop index value
}
// foo reverts to original value of 1 after loop terminates
```

---
[Index](index.md) | Next: [Functions](functions.md)
