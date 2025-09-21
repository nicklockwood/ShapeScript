Import
---

## Scripts

ShapeScript files can get quite large for complicated scenes, and you may find that there are common shapes that you wish to across multiple ShapeScript files. The `import` command can help with both of these problems:

```swift
import "MyShape.shape"
```

Here we've used `import` to load an external ShapeScript file and evaluate it inside the calling script. Any symbols that are defined in the imported file will become available inside the [scope](scope.md) in which it is loaded, and any geometry created by the imported file will be displayed.

You can import the same file several times in the same script, and import statements can appear inside [loops](control-flow.md#loops), [if statements](control-flow.md#if-else) or [blocks](blocks.md). If you don't want the geometry inside an imported file to be displayed immediately, you can place the import inside a [define](symbols.md) statement:

```swift
define ball {
    import "Ball.shape"
}
```

In this way, the loaded shape is bound to a symbol of your choice, and can be used a later point in the script. This approach also prevents any [symbols](symbols.md) defined in the imported script from leaking outside into the calling script's global [scope](scope.md).

**Note:** As with textures, the first time you try to import a file you may see an [access permission](materials.md#access-permission) warning.

## Models

The `import` command is not limited to loading `.shape` files, it can also load 3D models in a variety of standard formats:

Extension             | File Type                                        
:-------------------- | :------------------------------------------------
abc                   | Alembic                                          
dae                   | COLLADA Digital Asset Exchange                     
obj                   | Wavefront Object                
off                   | Object File Format    
ply                   | Polygon File Format                       
scn / scnz            | SceneKit Scene     
stl / stla            | Stereolithography                       
usd / usdz            | Universal Scene Description                     

<br/>

Imported models can be used just like imported script files. Importing a model inserts it directly into your scene:

```swift
import "Rocket.obj"
```

Or you can [define a symbol](symbols.md) for the model, to be used later:

```swift
define rocket import "Rocket.obj"
```

Depending on the format, imported models may include their own materials. Uncolored / untextured models can be styled in the normal way by using [material](materials.md) commands:

```swift
define rocket {
    texture "Rocket.png"
    import "Rocket.obj"
}
```

## Text and Data

In addition to scripts and 3D models, plain text files can be imported as a [string](literals.md#strings) value.

```swift
define text import "Text.txt"
```

Imported strings can then be displayed directly, or further processed using ShapeScript's [string functions](functions.md#strings):

```swift
for line in text.lines {
    print (trim line)
}
```

ShapeScript also supports importing JSON files as [structured data](literals.md#structured-data):

```swift
define data import "Data.json"
```

**Note:** ShapeScript currently only supports `txt` or `json` file extensions for data files. To import structured text in other formats you will need to change the file extension.

## Dynamic Imports

It can sometimes be useful to generate the name of an imported file dynamically. For example if you have multiple numbered files to import, you might want to generate the names programatically.

You can do this using the [text interpolation](text.md#interpolation) feature. The following code, for example, will load the files "Shape1.shape", "Shape2.shape"... up to "Shape10.shape":

```swift
for n in 1 to 10 {
    import "Shape" n ".shape"
}
```

---
[Index](index.md) | Next: [Export](export.md)
