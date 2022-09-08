Camera Control
---

When you open a file in ShapeScript, it is rendered in 3D using a virtual camera, which can be controlled via touch gestures. The camera is not part of the file itself, and moving it will not change the file in any way.

## Camera Selection

By default, the camera is positioned along the Z axis, looking down at the model. The distance of the camera from the origin is set automatically based on the bounding sphere of the model.

You can choose a different camera angle from the camera menu in the top right of the screen. Custom cameras [can be defined](cameras.md) programatically. To reset the current camera to its default position, select `Reset View`.

## Touch Controls

Motion                       | Action
:--------------------------- | :--------------------------
Rotate model                 | Swipe with one finger
Pan up/down/left/right       | Swipe with two fingers
Zoom in and out              | Pinch
Roll                         | Pinch, then rotate fingers

## Copy Settings

To copy the configuration for the current camera view, select `Copy Settings` from the camera menu. This will copy a snippet of ShapeScript code which you can then paste into your `.shape` file to define a [custom camera](cameras.md#custom-cameras).

---
[Index](index.md) | Next: [Primitives](primitives.md)
