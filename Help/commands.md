Commands
---

Like [options](options.md), and [functions](functions.md), commands in ShapeScript are denoted by a keyword followed by zero or more values or expressions. Different commands accept different value types, but typically these will be a number, vector, text or a [block](blocks.md).

```swift
detail 5 // a numeric argument

translate 1 0 -1 // a vector argument

texture "world.png" // a text argument
```

The values passed to a command can be anything from simple literal values, to symbol references, to whole expressions.  For example:

```swift
rotate 1 + angle 0 0
```

In the case above, the `roll` parameter of the `rotate` command has been given a value of `1 + angle`, and the `yaw` and `pitch` parameters are zero. Expressions can be a bit confusing to read inside vector parameters due to the differing significance of spaces between values, so for clarity you may wish to add parentheses:

```swift
rotate (1 + angle) 0 0
```

Commands do not *necessarily* accept or return a value. The main distinction between commands and functions/constants is that commands have *side effects*. Typically they either alter the appearance of the model, or alter the effects of subsequent commands. Here are some examples:

ShapeScript has a number of built-in commands:

## Detail

The `detail` command can be used anywhere in the ShapeScript file to override the local detail level used for approximating curved geometry. It is documented in the [options](options.md#detail) section.

## Materials

The `color`, `texture` and `opacity` commands are used to specify the appearance of shapes when rendered. These commands are documents in the [materials](materials.md) section.

## Font

The `font`, command is used to specify the font used to render [text](text.md). 

## Transforms

The `rotate`, `translate` and `scale` commands are useful for procedurally generating paths and complex shapes. These are documented in the [transforms](transforms.md#relative-transforms) section.

## Primitives

The `cube`, `sphere`, `cone` and `cylinder` commands are used to generate simple 3D shapes that can be composed into more complex forms. They are documented in the [primitives](primitives.md) section.

## Paths

The `path`, `circle` and `square` commands are used to create paths that can be used as the inputs for `builder` commands that can generate complex 3D shapes. They are documented in the [paths](paths.md) section.

## Text

The `text` command is used to generate individual words, lines or paragraphs of text, which can then be [filled](builders.md#fill) or [extruded](builders.md#extrude) to create a 3D mesh. The `text` command is documented in the [text](text.md) section.

## Builders

The `fill`, `lathe`, `extrude` and `loft` commands turn paths into 3D meshes. They are documented in the [builders](builders.md) section.

## Constructive Solid Geometry (CSG)

The `difference`, `union`, `intersection` and `stencil` commands use boolean operations to merge or subtract shapes from each other to form surfaces that would be hard to model directly. They are documented in the [CSG](csg.md) section.

## Random Numbers

The `rnd` and `seed` commands can be used to generate pseudorandom values that are great for procedurally generating natural-looking shapes. The [train example](examples.md#train) uses this approach to create a jumbled layer of coal behind the driver's cab.

The `rnd` command takes no parameters but returns a random number in the range 0 to 1. It can be used as one of the inputs to a `rotate` or `translate` command, or multiplied by other values as part of an expression to produce random numbers in different ranges:

```swift
// randomly position a cube between -5 and +5 on the y axis
cube { position 0 (rnd * 10) - 5 0 }
```

Each time `rnd` is called it will return a different value. Numbers are returned in a deterministic but non-repeating sequence. Because the sequence is deterministic, it will always produce the same values each time your model is rendered.

To alter the random sequence you can use the `seed` command. The `seed` command takes a numeric value as its argument, and this is used to generate all subsequent `rnd` values. The seed value can be any number (positive or negative, integer or fraction), but note that values outside the range 0 to 2<sup>32</sup> will be wrapped to that range.

If you are not happy with how some randomly generated geometry looks, try setting the seed to an arbitrary value, and keep tweaking it until you like the result:

```swift
seed 57
```

You can reset the `seed` at any point within your ShapeScript file, and it will alter the sequence for subsequent `rnd` calls. Like most other commands, `seed` is scoped, so setting the `seed` inside a [group](groups.md) or [block](blocks.md) will only apply to `rnd` calls within that block, and `rnd` commands after the closing `}` will use the previously-specified `seed` value.

The default starting value for `seed` is zero, so `seed 0` will cause the `rnd` sequence to repeat from the beginning. Remember that the sequence produced from a given seed is always the same, so re-using the same seed value multiple times in your script will result in repetition of the same random sequence.

## Logging

When creating complex scripts, it can sometimes be difficult to understand what's happening in the code. To help you debug your scripts, you can use the `print` command:

```swift
print 5 + 6

print "some text"

print someValue
```

The `print` command accepts one or more arguments of any type. You can use this to intersperse values and text labels for example:

```swift
print "width =" width

print "x:" x "y:" y
```

Printed values are displayed in a console area below the scene. The console can be resized and scrolled to show as much text as you need.


---
[Index](index.md) | Next: [Loops](loops.md)
