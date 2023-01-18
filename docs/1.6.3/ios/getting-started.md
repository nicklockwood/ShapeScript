Getting Started
---

ShapeScript Viewer for iOS is designed for opening and editing 3D models and scenes that use the ShapeScript `.shape` file format.

If you do not have any existing ShapeScript files, you can create one using the `+` button. You will be prompted to select a name and location for your new file - you can call it anything you want, but be sure to retain the `.shape` file extension.

![New file modal](../../images/new-file-ios.png)

After pressing OK you should see a new screen appear containing a cube, sphere and cone. These are the default contents for a new file (don't worry, you can replace them with your own shapes).

![New document window](../../images/new-document-ios-1.6.3.png)

## Viewing

Drag your finger inside the window and you will notice that the three shapes appear to rotate.

You are not actually moving the shapes themselves, but rotating the camera around them. To return to the original orientation, tap the camera icon in the top-right and select `Reset View`.

To help you orient yourself, you can enable the `Show Axes` option in the camera menu, which displays the direction of the X, Y and Z axes.

![Show axes](../../images/show-axes-ios-1.6.3.png)

For more information about navigating around the scene, see [Camera Control](camera-control.md).

## Editing

To edit your `.shape` file, tap the pencil icon in the top-right of the screen. This will open the file inside the integrated source editor:

![Integrated source editor](../../images/source-editor-ios.png)

Changes made to the model in the source editor will be reflected immediately in the scene (although you may need to close the source view to see them!).

In addition to the built-in editor, ShapeScript also supports the use of external text editors such as [Runestone](https://apps.apple.com/app/runestone-text-editor/id1548193893) or [Subtext](https://apps.apple.com/app/subtext/id1606625287).

ShapeScript files are just ordinary text documents, so they can be opened in any program that supports editing text. No third-party editors currently support ShapeScript syntax directly, but if you set your editor to treat `.shape` files as another C-like language (e.g. C, Swift or Java) then it should do an acceptable job of syntax coloring and indenting. Some editors (such as Runestone) will make this association automatically, which will save you having to do it each time you edit a ShapeScript file.

If you are using an iPad, you can use the [Split View](https://support.apple.com/en-gb/guide/ipad/ipad08c9970c/ipados) feature to show both ShapeScript Viewer and your text editor app on screen simultaneously:

![Split View](../../images/split-view-ios-1.6.3.png)

**Note:** Not all iOS text editors support *live editing* (where changes in the text are reflected automatically in ShapeScript as you make them). You may find you have to explicitly save or close the document in your editor for changes to take effect. External editors may also not immediately pick up changes you make using the built-in source editor, so be careful when switching between them.

## File Structure

The first line of the default `.shape` document looks like this:

```swift
// ShapeScript document
```

Lines beginning with `//` are comments, and are ignored by the parser. You can use these comments to document what the different parts of your file are doing.

The next line is:

```swift
detail 32
```

This controls the level of detail used for shapes in the file. The shapes are made out of flat polygons, so it is not possible for curved edges to be represented exactly. When you define a sphere or other curved shape, the `detail` value is used to decide how many polygons will be used.

Next we have the following:

```swift
cube {
    position -1.5
    color 1 0 0
}
```

These three lines (ignoring the closing `}`) represent three distinct instructions, although they are grouped together because they all relate to a single shape. White space (such as spaces, tabs, or blank lines) is mostly ignored, however each new instruction must be placed on a new line.

The first instruction, `cube`, creates the cube shape. Note the `{ ... }` braces after `cube`. Content inside braces relates to the instruction that precedes them. In this case, the braces contain instructions that set the  `position` and  `color` of the cube.

The line `position -1.5` means "position the shape 1.5 spacial units to the left of the origin". The *origin* is the center of the world, and is the default position at which new shapes will appear.

**Note:** The spacial units ShapeScript uses are arbitrary, and can represent anything that you wish them to: a centimeter, a meter, an inch, a mile, etc. Try to choose an appropriate scale for your scene so that you avoid having to work with very large numbers (thousands of units), or very small ones (thousandths of a unit). That will help to avoid rendering precision issues, as well as making your scripts easier to work with.

The `position` keyword is followed by up to 3 numbers representing offsets along the X, Y, and Z axes respectively. If values are omitted, they are assumed to be zero, so a position o-f `-1.5` is equivalent to `-1.5 0 0`. This is covered in detail in the [transforms](transforms.md#position) section.

The next line, `color 1 0 0` sets the current color. The three numbers after the keyword represent the red, green, and blue color channels, each with a range from 0 to 1. Because the red channel is 1 and the other channels are 0, the resultant color will be pure red.

As with `position`, you can omit values for the `color`, but the behavior is slightly different: If you only specify one value then that will be used for all three color channels. You can optionally specify a fourth "alpha" value to control transparency. This is covered in detail in the [materials](materials.md#color) section.

The groups of instructions after the cube are similar, but define a sphere and cone respectively.

## Next Steps

Change the `color 1 0 0` instruction to `color 1 1 0`, and then save the file. If you switch back to the ShapeScript app you should now see that the red cube has changed to yellow. ShapeScript tracks changes to any open files and will automatically update the view whenever they are saved.

![Yellow cube](../../images/yellow-cube-ios-1.6.3.png)

Try tweaking the values for the `position`  and `color` instructions and observing the effects. You could also try adding a `size` option, which works like the others, but controls the *size* of the shape.

If you make a mistake, you will see a screen like this:

![Error screen](../../images/error-screen-ios-1.6.3.png)

There is no cause for alarm if you see this screen. Just fix your mistake and save again to clear the error. If you aren't sure what you did, and the error message doesn't help, use undo feature in your editor to backtrack to a working state and try again.

When you are comfortable with manipulating the default shapes, try deleting them and adding new ones of your own.

**Note:** Many text editors save automatically every few seconds, so you may find that ShapeScript applies your changes as you type, even if you haven't explicitly saved. If you are in the middle of typing a new command when the automatic refresh takes place, ShapeScript may display an error, just as if you had manually saved an incomplete file. Errors that appear while you are still typing can be safely ignored.

## Debugging and Selection

To get information about your scene (such as polygon count and overall dimensions), tap the info button in the top-right corder of the screen.

To get info about a particular shape in the scene, tap on it in the viewer to select it then press the info button. This will also tell you which line in the `.shape` file defines that component. Tap outside of the shape to deselect it again.

![Object info](../../images/object-info-ios-1.6.3.png)

**Note:** If you are having trouble identifying a particular shape from your `.shape` file, you can use the [debug command](debugging.md) to highlight it in the viewer.

---
[Index](index.md) | Next: [Camera Control](camera-control.md)
