Camera Control
---

When you open a file in ShapeScript, it is rendered in 3D using a virtual camera, which can be controlled either programmatically or via touch gestures.

## Camera Selection

The camera defaults to "Front" view, which is positioned along the Z axis, looking forward towards the scene. The distance of the camera from the origin is set automatically based on volume occupied by the shapes in the scene.

You can choose a different camera angle from the camera menu in the top right of the screen. [Custom cameras](cameras.md#custom-cameras) can be defined programatically. ShapeScript will remember the last selected camera for each shape file.

To temporarily change the camera position, you can alter the view using touch gestures (see below). To reset the current camera back to its original position, select `Reset View`.

## Touch Controls

Motion                       | Action
:--------------------------- | :--------------------------
Rotate scene                 | Swipe with one finger
Pan up/down/left/right       | Swipe with two fingers
Zoom in and out              | Pinch
Roll                         | Pinch, then rotate fingers

## Copy Settings

It can be difficult to visualize the effect that a given position or orientation will have when defining a [custom camera](cameras.md#custom-cameras). A good solution is to use touch gestures to position the camera, then select `Copy Camera Settings` from the camera menu.

This copies a snippet of ShapeScript code which you can then paste into your `.shape` file to create the custom camera.

---
[Index](index.md) | Next: [Primitives](primitives.md)
