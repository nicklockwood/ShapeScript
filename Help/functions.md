Functions
---

Functions consist of a name followed by one or more values. They perform an operation on their input values and return the result.

Functions are *pure*, meaning that they do not have *side-effects*, and they do not depend on the current state of the program. A function called with a given set of input values will always return the same output value.

Functions can be used inside expressions, and can accept expressions as inputs. Unlike [operators](operators.md), functions have no implicit precedence, so parentheses may be needed to avoid ambiguity.

In the following example, it's not clear if `y` is intended as a second argument to the `cos` function, or as the second argument to the translate command. Only the latter would technically be valid, since `cos` only accepts a single argument, but ShapeScript requires you to be explicit, and will treat this as an error:

```swift
translate cos x y
```

The error can be resolved by using parentheses to group the `cos` function with its argument:

```swift
translate (cos x) y
```

Lisp programmers will find this syntax quite familiar, but if you have used C-like programming languages it may seem a little strange to put the parentheses around the function name and its arguments instead of just the arguments. If you prefer, you can use a C-like syntax instead:

```swift
translate cos(x) y
```

Either approach is acceptable in ShapeScript. Note however that in the latter case there must be no space between the function name and the opening paren.

## Math functions

In addition to the standard math [operators](operators.md), ShapeScript also includes a number of built-in math *functions*:

The `round` function is used to round a number to the nearest integer (whole number):

```swift
round 3.2 // returns 3
round 3.9 // returns 4
round 3.5 // returns 4
```

The  `floor`  function is similar, but always rounds down:

```swift
floor 3.2 // returns 3
floor 3.9 // returns 3
```

The  `ceil`  function always rounds up:

```swift
ceil 3.2 // returns 4
ceil 3.9 // returns 4
```

The `abs` function returns the magnitude of a number, ignoring the sign:

```swift
abs 4.5 // returns 4.5
abs -51 // returns 51
```

The `sqrt` function returns the square root of a value:

```swift
sqrt 4 // returns 2
sqrt 2 // returns 1.41421… 
```

The `pow` function takes *two* parameters, and return the first value raised to the power of the second:

```swift
pow 2 4 // returns 16
pow 3 2 // returns 9
pow 4 0.5 // returns 2
```

The `min` function returns the lower of two values:

```swift
min 2 4 // returns 2
min 5 -5.1 // returns -5.1
```

The `max` function returns the higher of two values:

```swift
max 2 4 // returns 4
max 5 -5.1 // returns 5
```

## Trigonometry

For the most part, you can avoid the need for trigonometry is ShapeScript by using the built-in [transform commands](transforms.md#relative-transforms) to manipulate geometry rather than manually calculating the positions of vertices.

But sometimes you may wish to do something more complex (e.g. generating a path in the shape of a sign wave) that can only be achieved through explicit calculations, and to support that, ShapeScript provides a standard suite of trigonometric functions.

**Note:** while ShapeScript's transform commands generally expect angles in the range 0 to 2, the trigonometric functions all use radians. To convert an angle in radians to a ShapeScript rotation value, divide it by `pi` :

```swift
define angle acos(0.5) // 60 degrees
rotate angle / pi
``` 

The `sin` function returns the sine of an angle (specified in radians):

```swift
sin pi / 2 // returns 1
``` 

The `cos` function returns the cosine of an angle (specified in radians):

```swift
cos pi // returns -1
``` 

The `tan` function returns the tangent of an angle (specified in radians):

```swift
tan pi / 4 // returns 1
``` 

The `asin` function computes the inverse sine function (aka arc sine), returning an angle in radians:

```swift
asin 1 // returns pi / 2
``` 

The `acos` function computes the inverse cosine function (aka arc cosine), returning an angle in radians:

```swift
acos -1 // returns pi
``` 

The `atan` function computes the inverse tangent function (aka arc tangent), returning an angle in radians:

```swift
atan 1 // returns pi / 4
``` 

The `atan2` function works like `atan`, but instead of a single tangent value, it accepts an x and y value and returns the angle of the vector that they describe. The resultant angle correctly takes the vector quadrant into account:

```swift
atan2 1 -1 // returns pi * 0.75
``` 

---
[Index](index.md) | Next: [Commands](commands.md)
