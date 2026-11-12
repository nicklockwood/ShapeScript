Camera Control
---

When you open a file in ShapeScript, it is rendered in 3D using a virtual camera, which can be controlled either programmatically or via mouse or trackpad.

## Camera Selection

The camera defaults to "Front" view, which is positioned along the Z axis, looking forward towards the scene. The distance of the camera from the origin is set automatically based on volume occupied by the shapes in the scene.

You can choose a different camera angle from the `View > Camera` menu. [Custom cameras](cameras.md#custom-cameras) can be defined programatically. ShapeScript will remember the last selected camera for each shape file.

To temporarily change the camera position, you can alter the view using the mouse or trackpad (see below). To reset the current camera back to its original position, select the `View > Camera > Reset` menu, or press **Cmd-0** on the keyboard.

## Mouse Control

**Note:** The instructions below assume the use of an Apple Magic Mouse. Controls for other mice may differ.

Motion                       | Action
:--------------------------- | :--------------------------
Rotate scene                 | Hold the mouse button and drag
Pan up/down/left/right       | Either swipe the mouse surface with one finger, or hold Shift + mouse button and drag
Zoom in and out              | Hold Shift, then swipe up or down on the mouse surface with one finger

<br/>

## Trackpad Control

Motion                       | Action
:--------------------------- | :--------------------------
Rotate scene                 | Click and drag with one finger
Pan up/down/left/right       | Swipe with two fingers
Zoom in and out              | Either pinch, or hold Shift + swipe up or down with two fingers
Roll                         | Pinch, then rotate fingers

<br/>

## Copy Settings

It can be difficult to visualize the effect that a given position or orientation will have when defining a [custom camera](cameras.md#custom-cameras). A good solution is to use touch gestures to position the camera, then select `View > Copy Camera Settings`, or press **Cmd-Shift-C** on the keyboard.

This copies a snippet of ShapeScript code which you can then paste into your `.shape` file to create the custom camera.

---
[Index](index.md) | Next: [Primitives](primitives.md)
