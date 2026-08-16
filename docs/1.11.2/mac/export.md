Export
---

Once you've finished crafting your 3D scene, you'll probably want to *do something* with it. For that you will need to use the *Export* feature.

**Export is a paid upgrade that can be unlocked via in-app purchase in the [ShapeScript Mac App](https://apps.apple.com/app/id1441135869). Export is not available in the free ShapesScript Viewer.**

To export your scene, select the `File > Unlock Export Feature…`  menu (**Cmd-Shift-E**) to unlock the export functionality. Once unlocked, this menu will change to `Export…`.

**Note:** The export menu will be greyed out if the scene does not contain any exportable geometry.

## Model and Scene Formats

ShapeScript can export your scene in a variety of formats, selectable from the export window:

Extension             | File Type
:-------------------- | :-------------------------------
3mf                   | 3D Manufacturing Format
abc                   | Alembic
csg / scad            | OpenSCAD CSG
dae                   | COLLADA Digital Asset Exchange
obj                   | Wavefront Object
off                   | Object File Format
ply                   | Polygon File Format
scn / scnz            | SceneKit Scene
stl / stla            | Stereolithography
usd / usdz            | Universal Scene Description

<br/>

**Note:** Not all formats support all features of ShapeScript scenes, so you may need to experiment.

Some model formats do not support embedding geometry and textures or materials in a single file; In this case, ShapeScript will export a folder containing the model and associated assets as separate files.

Exported models can be used in a variety of ways:

## Games and AR

Models exported from ShapeScript are well-suited to use in realtime 3D because the `detail` command gives you fine control over the triangle count. For realtime use you should generally set the detail level as low as you can get away with.

You can import DAE or OBJ files into a game development tool like Unity, or use USD(Z) files with Apple's SceneKit and RealityKit frameworks in Xcode.

## 3D Printing

ShapeScript can export models in the 3D Manufacturing Format (3MF) and Stereolithography (STL) format used by many 3D printing applications. Both binary and ASCII STL files are supported, but binary is recommended for file size and compatibility reasons. To export as ASCII use the `.stla` file extension, but note that you may need to rename the extension to `.stl` for it to be recognized by some applications.

When exporting for 3D printing, you will usually want to avoid having internal geometry inside the outer surface of your model. A good way to do this is to use the [union](csg.md#union) command to combine overlapping parts of your model into a single shape, eliminating internal faces.

You can also uses the [mesh](meshes.md) command to flatten a shape into a mesh without altering its geometry. This can be useful for ensuring that curves or text are preserved exactly when exporting with the OpenSCAD CSG format. It's also useful if you intend to use the CSG file with applications like FreeCAD that do not support all of the features.

ShapeScript scenes use the "Y-up" convention, where the Y-axis points up and the Z-axis points out from the screen. Some popular 3D printing applications such as [Cura](https://ultimaker.com/software/ultimaker-cura) use the "Z-up" convention instead. Check the "Convert to Z-Up" option in the export window to export your model in this orientation.

## Plotters and CNC Machines

Extension             | File Type
:-------------------- | :-------------------------------
svg                   | Scalable Vector Graphics

By selecting the SVG option, you can export your model as a 2D cross-section. Unlike the other model export formats, the SVG export option does not preserve any depth or material information, but simply takes a slice across the XY plane and captures a vector outline suitable for printing or carving by a [plotter](https://en.wikipedia.org/wiki/Plotter) or [CNC machine](https://en.wikipedia.org/wiki/Numerical_control).

## Image Formats

In addition to 3D models and 2D vector paths, ShapeScript can also export bitmap images. By default, images will be captured using the current camera, but you can select a different [camera view](cameras.md) from the export window.

The following image formats are supported:

Extension             | File Type                                         | Supports Transparency
:---------------------| :-------------------------------------------------|:------------------------------
gif                   | Graphics Interchange Format                       | Yes
png                   | Portable Network Graphics                         | Yes
jpg / jpeg            | Joint Photographic Experts Group                  | No
jpf / jp2             | JPEG 2000                                         | Yes
tif / tiff            | Tagged Image File Format                          | Yes
bmp                   | Bitmap                                            | No

<br/>

If you aren't sure which format to use, the PNG format is a good all-rounder, with lossless compression and transparency support.

## Image Options

The size of the exported image defaults to the current window size at the current display resolution. You can override this size in your script file by adding `width` and/or `height` options to your [custom camera](cameras.md#pixel-dimensions), or by clicking on the size label in the export window and selecting a different size:

![Export size](../../images/export-size.png)

Images are exported with a transparent background by default if the selected format supports it, or white otherwise. To change the background color or set a background image, you can use the [background command](commands.md#background). If you are planning to composite the image onto a different background later, you may wish to disable [antialiasing](cameras.md#antialiasing).

When exporting an image (or exporting a model for non-realtime use) you can improve the quality by using the `detail` command. A detail level of 100 should be good enough for even a very large or high-resolution image, but this can take a long time to generate/render.

**Note:** Although ShapeScript can export images, for best results you should export as a 3D model and then import that into a [ray tracing](https://en.wikipedia.org/wiki/Ray_tracing_(graphics)) program that provides fine-grained control over scene lighting and camera placement.

## Command-Line Export

A separate `shapescript` command-line tool is available for exporting files from Terminal. This is useful when you want to script exports, bulk-export a folder of `.shape` files, or generate ShapeScript output as part of an automated build process. See [Command Line Tool](cli.md) for installation instructions.

On macOS, command-line export requires an unlocked copy of the ShapeScript Mac app to be installed on the same machine. Without Export unlocked, the command-line tool can still check `.shape` files and report errors, but it cannot write exported files.

The Linux command-line tool does not require the Mac app or an Export unlock, but it is limited to `.stl` or `.stla` export.

To export a file using the command-line tool, pass the input `.shape` file followed by the output path:

```bash
shapescript myfile.shape myfile.stl
```

The output file extension selects the export format. On macOS, the command-line tool supports the same [model and scene formats](#model-and-scene-formats), [SVG cross-section export](#plotters-and-cnc-machines), and [image formats](#image-formats) described above.

Use the `--z-up` option when exporting model files for tools that expect Z to be the vertical axis:

```bash
shapescript myfile.shape myfile.stl --z-up
```

This is the command-line equivalent of the "Convert to Z-Up" option described in the [3D Printing](#3d-printing) section.

On macOS, the command-line tool can also export the [image formats](#image-formats) listed above. When exporting images, you can choose the camera and output size from Terminal:

```bash
shapescript myfile.shape myfile.png --camera "Side View"
shapescript myfile.shape myfile.png --width 1024 --height 768
```

The `--camera` option accepts the built-in camera names `Front`, `Back`, `Left`, `Right`, `Top`, and `Bottom`, or the `name` of a custom camera defined in the script.

The `--width` and `--height` options set the exported image dimensions; if only one dimension is supplied, the other is derived from the selected camera's aspect ratio. See [Image Options](#image-options) for more about image size, background transparency, antialiasing, and detail level.

---
[Index](index.md) | Next: [Command Line Tool](cli.md)
