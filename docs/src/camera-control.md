Camera Control
---

When you open a file in ShapeScript, it is rendered in 3D using a virtual camera, which can be controlled via a mouse or trackpad. The camera is not part of the file itself, and moving it will not change the file in any way.

## Camera Selection

By default, the camera is positioned along the Z axis, looking down at the model. The distance of the camera from the origin is set automatically based on the bounding sphere of the model.

You can choose a different camera angle from the `View > Camera` menu. [Custom cameras](cameras.md#custom-cameras) can be defined programatically. To reset the current camera to its default position, select the `View > Camera > Reset` menu, or press **Cmd-0** on the keyboard.

## Mouse Control

**Note:** The instructions below assume the use of an Apple Magic Mouse. Controls for other mice may differ.

Motion                       | Action
:--------------------------- | :--------------------------
Rotate model                 | Hold the mouse button and drag
Pan up/down/left/right       | Either swipe the mouse surface with one finger, or hold Shift + mouse button and drag
Zoom in and out              | Hold Shift, then swipe up or down on the mouse surface with one finger

<br/>

## Trackpad Control

Motion                       | Action
:--------------------------- | :--------------------------
Rotate model                 | Click and drag with one finger
Pan up/down/left/right       | Swipe with two fingers
Zoom in and out              | Either pinch, or hold Shift + swipe up or down with two fingers
Roll                         | Pinch, then rotate fingers

<br/>

## Copy Settings

To copy the configuration for the current camera view, select `View > Copy Camera Settings`, or press **Cmd-Shift-C** on the keyboard. This will copy a snippet of ShapeScript code that you can paste into your `.shape` file to define a [custom camera](cameras.md#custom-cameras).

---
[Index](index.md) | Next: [Primitives](primitives.md)
