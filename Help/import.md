Import
---

ShapeScript files can get quite large for complicated models, and you may find that there are common shapes that you wish to across multiple ShapeScript files. The `import` command can help with both of these problems:

```swift
import "MyShape.shape"
```

The `import` command loads an external ShapeScript file and evaluates it inside the calling script. Any symbols that are defined in the imported file will become available inside the [scope](scope.md) in which it is loaded, and any geometry created by the imported file will be displayed.

You can import the same file several times in the same script, and import statements can appear inside [loops](loops.md) or [blocks](blocks.md). If you don't want the geometry inside an imported file to be displayed immediately, you can place the import inside a [define](symbols.md) statement:

```swift
define ball {
    import "Ball.shape"
}
```

In this way, the loaded shape is bound to a symbol of your choice, and can be used a later point in the script. This approach also prevents any [symbols](symbols.md) defined in the imported script from leaking outside into the calling script's global [scope](scope.md).

The `import` command is not limited to loading `.shape` files. It can load models in any of the [export formats](export.md) supported by ShapeScript. Imported models can be used just like imported script files:

```swift
define rocket {
    texture "Rocket.png"
    import "Rocket.obj"
}
```

Depending on the format, imported models may include their own [materials](materials.md). Uncolored / untextured models will inherit the current ShapeScript material properties.

---
[Index](index.md) | Next: [Examples](examples.md)
