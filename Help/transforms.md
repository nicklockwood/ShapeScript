Transforms
---

Every shape has a position, orientation and size. These can be set in *absolute* units by using the `position`, `orientation` and `size` options, or in *relative* units using the `translate`, `rotate` and `scale` commands (see [relative transforms](#relative-transforms) below).

## Position

When you define a shape in ShapeScript, it is created at the *point of origin*. By default, this is the zero position of the X, Y and Z axes within the current [scope](scope.md), but this can be overridden using the `position` option.

The `position` option accepts a [vector](literals.md#vectors-and-tuples) of up to 3 values representing a coordinate along the X Y and Z axes. If values are omitted they are assumed to be zero. The default `position` of every shape is `0 0 0`, which is located at the *origin*, aka the center of the world.

Positive `position` values move the shape right, up, and towards the camera respectively. Negative values move it left, down and away from the camera:

```swift
cube {
    position 0 0 5 // moves the cube 5 units towards the camera
}
```

Positions are applied hierarchically. For shapes located at the root of the ShapeScript file, their `position` is relative to the world origin, however you can nests shapes inside [groups](groups.md), in which case the `position` of the child shapes will be measured relative to the `position` of their containing group.

## Orientation

The `orientation` option defines the rotation for the shape using three parameters called `roll`, `yaw` and `pitch`.  The `roll` value represents a rotation around the Z axis, the `yaw` is rotation around the Y axis, and the `pitch` is a rotation around the X axis:

```swift
cube {
    orientation 0 0.25 0 // rotates the cube 45 degrees around the Y axis
}
```

The ordering of these three parameters may seem counterintuitive (Z, Y, X), but it makes sense in the context that when working with 2D [paths](paths.md), you often wish to apply a rotation only around the Z axis (in the XY plane), and by having that as the first parameter, you can simply omit the other values, which will default to zero.

Angles of rotation are specified as numbers in the range 0 to 2 (or 0 to -2 if you prefer), representing the number of half turns. This again may seem odd if you were expecting degrees or radians, but using this range works better mathematically, as you avoid the need to multiply or divide computed rotation values by [pi](https://en.wikipedia.org/wiki/Pi) or 180, and it's easier to mentally convert 90 degrees to 0.5 than to 1.5707963268 (see the [trigonometry section](functions.md#trigonometry) for more about converting between angular representations).

While it is relatively simple to use the `orientation` property to specify a rotation around a single axis, it can be awkward to apply a rotation around multiple axes at once due to the fixed order. If you need to do that, you may find it simpler to use the `rotate` command instead (described [below](#relative-transforms)), which can be applied multiple times in any order.

## Size

The `size` option applies a scaling factor to all subsequent geometry. A scale factor of `0.5 0.5 0.5` for example, would halve the size of all subsequent shapes, as well as halving the offset applied by subsequent `translate` commands.

Like the `position` and `orientation` commands, `size` allows you to omit one or two parameters, however unlike the other commands, omitted parameters are assumed to be equal to the first value given. So `size 0.5` is equivalent to `size 0.5 0.5 0.5`.

It it possible to apply a negative scale factor, which has the effect of flipping the geometry. For example, `size 1 -1 1` would flip all subsequent shapes upside-down along the Y axis. This does not always work as intended however, and may produce odd side-effects such as turning shapes inside-out. In general it is better to stick to positive `size` values, and use `orientation` if you need to flip a shape around.

## Relative Transforms

When defining paths or shapes procedurally using [loops](control-flow.md#loops) or other logic, you will often wish to position shapes or points using *relative* coordinates, rather than absolutely. You can do this using the `translate`, `rotate` and `scale` commands, which are counterparts to the `position`, `orientation` and `size` options.

Translation is the mathematical term for directional movement. Like `position`,  `translate`  takes up to 3 values representing offsets along the X Y and Z axes. Unlike `position`, the values do not specify the position of the containing shape, but rather they move the *origin* of the current [scope](scope.md), affecting all subsequently defined shapes.

The two following examples are therefore equivalent:

```swift
cube { position 1 0 0 }
```

```swift
translate 1 0 0
cube
```

In both cases, the cube is moved one unit to the right. But whereas in the first example the cube itself has been moved, in the second example, the *world* has been moved.

This distinction doesn't matter much until you create another shape. In the first example, the effect of setting the `position` is limited to the cube itself, and subsequent shapes will be unaffected. However in the second example, all subsequent shapes will also be shifted by one unit to the right.

You can prevent this by using another `translate` to move the origin back to its original position:

```swift
translate 1 0 0
cube // located at 1 0 0
translate -1 0 0
sphere // located at 0 0 0
```

Just as the `translate` command moves the origin, the `rotate` command rotates it, and the `scale` command increases or decreases the scale factor. These are equivalent:

```swift
cube {
    size 2
    orientation 0.25
}
```

```swift
scale 2
rotate 0.25
cube
```

And as with `translate`, in the second case the rotation and scale will be permanently altered for all future shapes, so to reset them you would need to apply the inverse transforms:

```swift
scale 2
rotate 0.25
cube
rotate -0.25
scale 0.5
```

As mentioned in the [orientation](#orientation) section above, an advantage of the `rotate` command is that it allows you to apply rotations in any order. For example the following code applies a pitch of 45 degrees followed by a roll of 80 degrees, which would be very difficult to express as a single `rotate` or `orientation` instruction due to the fixed roll-yaw-pitch order:

```swift
rotate 0 0 0.25 // pitch 45 degrees
rotate 0.4 0 0 // roll 80 degrees
cube
```

---
[Index](index.md) | Next: [Bounds](bounds.md)
