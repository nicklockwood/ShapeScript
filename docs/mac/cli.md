Command Line Tool
---

The `shapescript` command-line tool is available as a separate download from the [ShapeScript GitHub releases page](https://github.com/nicklockwood/ShapeScript/releases), and is available for both macOS and Linux. It can check `.shape` files from Terminal, report script errors, and export models or images without opening a document window. This makes it useful for scripting workflows, bulk-exporting multiple files, and integrating ShapeScript into automated build pipelines.

On Mac, exporting from the command-line tool requires an unlocked copy of the ShapeScript Mac app to be installed on the same machine. You can still use the command-line tool to check files and report errors without unlocking Export.

## Installation

You can download the latest ShapeScript CLI for Mac or Linux from the [release page](https://github.com/nicklockwood/ShapeScript/releases/latest), or install it to `$HOME/.local/bin` by running this command in Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/nicklockwood/ShapeScript/HEAD/Viewer/CLI/install.sh)"
```

The installer downloads the correct prebuilt release for your platform and installs `shapescript` to `$HOME/.local/bin`. The prebuilt Linux binary is for x86_64 Ubuntu. Other Linux distributions may work, but Ubuntu is the supported target for the prebuilt download.

If `shapescript` is not found after installation, add `$HOME/.local/bin` to your shell path. For the default macOS shell use:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
```

For Bash or Linux:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

To check the installed version, open a new Terminal window after changing your shell path, then run:

```bash
shapescript --version
```

## Usage

Run `shapescript` with a `.shape` file to display [scene info](getting-started.md#debugging-and-selection) and report any errors:

```bash
shapescript myfile.shape
```

To export the file, pass an output path:

```bash
shapescript myfile.shape myfile.stl
```

See [Command-Line Export](export.md#command-line-export) for more information.

## Building from Source

You can also build the command-line tool from source. This builds the feature-limited open source version used for the Linux build, not the full macOS version described above.

To build directly with Swift Package Manager, install the [latest Swift toolchain](https://www.swift.org/download/), then run:

```bash
git clone https://github.com/nicklockwood/ShapeScript
cd ShapeScript
swift build -c release
```

Alternatively, [Mint](https://github.com/yonaskolb/Mint) users can install the latest version with:

```bash
mint install nicklockwood/ShapeScript
```

Mint installs command-line tools to `$HOME/.mint/bin`, so make sure that directory is included in your shell path if `shapescript` is not found after installation.

---
[Index](index.md) | Next: [Examples](examples.md)
