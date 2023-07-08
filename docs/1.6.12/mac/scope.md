Scope
---

## Block Scope

ShapeScript programs are hierarchical, with `{ ... }` braces used to denote the start and end of a block of related options or commands.

When you define symbols, the effect is limited to the *scope* of the current block, meaning that once the block exits (i.e. when the closing `}` is reached), and symbols defined inside it are discarded, and symbols whose values were overridden inside the block will revert to the value they had before the block was entered.

Block scope is not just limited to symbols; it also affects [materials](materials.md) and [transforms](transforms.md). When you use the `translate`, `rotate` and `scale` commands to modify the world-transform, or use `color` or `texture` to modify the current material, the effect of those changes is limited to the current block.

This is convenient, because it means that code that defines subcomponents in your scene can use transforms and materials internally without them "leaking out" and affecting other objects.

## Function Scope

When you define a [custom function](functions.md#custom-functions), it also creates a local scope around its body. Like blocks, functions inherit symbols from their parent scope and locally defined symbols will not *leak* out into their parent scope. Unlike blocks, functions can affect the transforms and materials of the scope where they are invoked.

## Conditional Scope

Control flow statements like [for loops](control-flow.md#loops) and [if statements](control-flow.md#if-else) also creates a local scope around their body. Like function scope, loop and if/else scope does not apply to transforms or materials, but only to symbols created using the `define` command.

Any symbols defined inside a `for` loop will be restricted to the inside of the loop body. This also applies to the optional loop index variable.

---
[Index](index.md) | Next: [Debugging](debugging.md)
