Functions
---

Functions consist of a name followed by one or more values. They perform an operation on their input values and return the result.

Functions can be used inside expressions, and can accept expressions as inputs. Unlike [operators](expressions.md), functions have no implicit precedence, so parentheses may be needed to avoid ambiguity.

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

Either approach is acceptable in ShapeScript.

## Arithmetic

In addition to the standard arithmetic [operators](expressions.md), ShapeScript also includes a number of built-in arithmetic *functions*:

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
sqrt 2 // returns 1.414
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

For the most part, you can avoid the need for trigonometry is ShapeScript by using the built-in [transform commands](transforms.md) to manipulate geometry rather than manually calculating the positions of vertices.

But sometimes you may wish to do something more complex (e.g. generating a path in the shape of a sign wave) that can only be achieved through explicit calculations, and to support that, ShapeScript provides a standard suite of trigonometric functions.

While ShapeScript's [transform](transforms.md) commands expect values in the range 0 to 2 (or 0 to -2), the trigonometric functions all use [radians](https://en.wikipedia.org/wiki/Radian).

While ShapeScript's [transform](transforms.md) commands expect values calculated by dividing the number of degrees by 180, the trigonometric functions all use radians, a value between 0 and 3.141 (pi).

For example, the `sin` (sine) function takes a radian representation of an angle and returns a ratio value of that angle. In this case 0.524 radians returns 0.5 or 1/2 - an angle of 30 degrees:

```swift
sin 0.524 // returns 0.5
``` 

The `acos` (arc cosine) function takes a ratio representation of an angle and returns a radians value of that angle. In this case 1/2 or 0.5 returns 1.047 radians - equivalent to an angle of 60 degrees:

```swift
acos 0.5 // return 1.047
``` 

The `cos` (cosine), `sin` (sine), and `tan` (tangent) functions all take a radians value and return a ratio value, and the `asin` (arc sine), `acos` (arc cosine), and `atan` (arc tangent) functions all take a ratio value and return a radians value.

Using `atan` to calculate the angle of a vector is problematic because the result that it returns can be ambiguous. You need to take the vector quadrant into account, as well as the ratio of the X and Y components.

The `atan2` function works like `atan`, but instead of a single tangent value, it accepts separate Y and X inputs and returns the angle of the vector that they describe. The resultant angle correctly takes the vector quadrant into account.

```swift
atan2 1 -1 // returns a radian angle of the vector Y: 1, X: -1
```

To convert an angle in radians to a ShapeScript rotation value, divide it by the 'pi' constant:

```swift
define angle acos(0.5) // returns 1.047 radians (60 degrees)
rotate angle / pi      // return 0.333 (1.047 / 3.141)
```

To convert a ShapeScript rotation value to radians, multiply it by `pi`.

```swift
cube {
    orientation 0.5
    print orientation.roll * pi // prints 1.571 (0.5 * pi)
}
```

Angular conversion formulae:

Conversion                      | Formula
:------------------------------ | :--------------------------
Degrees to radians              | radian = degrees / 180 * pi
Radians to degrees              | degrees = radians / pi * 180
Degrees to ShapeScript rotation | rotation = degrees / 180
ShapeScript rotation to degrees | degrees = rotation * 180
Radians to ShapeScript rotation | rotation = degrees / pi
ShapeScript rotation to radians | radians = rotation * pi

<br>

Common values:

Angle in degrees | Angle in radians | ShapeScript rotation 
:--------------- | :--------------- | :------------------
0                | 0                | 0
30               | pi / 6 (0.524)   | 1 / 6 (0.167)
45               | pi / 4 (0.785)   | 1 / 4 (0.25)
60               | pi / 3 (1.047)   | 1 / 3 (0.333)
90               | pi / 2 (1.57)    | 1 / 2 (0.5)

<br>

## Functions and Expressions

Expressions can be passed as function arguments, for example:

```swift
sin pi / 2 // returns 1
```

Which, thanks to precedence rules, is equivalent to:

```swift
sin(pi / 2) // returns 1
```

You can also use function calls *inside* an expression, for example:

```swift
print (sqrt 9) + (sqrt 9) // prints 6
```

Or the equivalent form of:

```swift
print sqrt(9) + sqrt(9) // also prints 6
```

**Note:** When used inside an expression, parentheses around the function (or just its arguments) are required.

## Custom Functions

You can define your own functions using the `define` command. A function definition consists of a function name followed by a list of parameter names in parentheses:

```swift
define sum(a b) {
    a + b
}

define degreesToRadians(degrees) {
    degrees / 180 * pi
}
```

Like [blocks](blocks.md), functions can refer to constant values or other functions defined in their containing [scope](scope.md):

```swift
define epsilon 0.0001

define almostEqual(a b) {
    abs(a - b) < epsilon
}
```

Unlike [block options](blocks.md), function inputs do not have default values. Calling a function without passing a value for every input will result in an error.

---
[Index](index.md) | Next: [Commands](commands.md)
