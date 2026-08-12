#!/bin/bash

# ShapeScript command-line tool installer.
#
# Installs the prebuilt `shapescript` CLI from the ShapeScript GitHub releases
# page to $HOME/.local/bin by default.

set -euo pipefail

REPO="nicklockwood/ShapeScript"
TOOL_NAME="shapescript"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${VERSION:-}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$TOOL_NAME-cli.XXXXXX")"
ZIP_PATH="$TMP_DIR/$TOOL_NAME.zip"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

case "$(uname -s)" in
    Darwin)
        PLATFORM="macos"
        ;;
    Linux)
        ARCH="$(uname -m)"
        if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
            echo "The ShapeScript command-line tool prebuilt Linux releases only support x86_64." >&2
            exit 1
        fi
        PLATFORM="linux-x86_64"
        ;;
    *)
        echo "The ShapeScript command-line tool prebuilt releases are only available for macOS and Linux." >&2
        exit 1
        ;;
esac

if [ -z "$VERSION" ]; then
    VERSION="$(
        curl -fsSLI -o /dev/null -w '%{url_effective}' \
            "https://github.com/$REPO/releases/latest" |
        sed 's#.*tag/##'
    )"
fi

if [ -z "$VERSION" ]; then
    echo "Could not determine the latest ShapeScript command-line tool release version." >&2
    exit 1
fi

echo "Installing the ShapeScript command-line tool..."

mkdir -p "$INSTALL_DIR"

curl -fsSL \
    "https://github.com/$REPO/releases/download/$VERSION/ShapeScriptCLI-$PLATFORM.zip" \
    -o "$ZIP_PATH"

unzip -oq "$ZIP_PATH" -d "$TMP_DIR"
install "$TMP_DIR/$TOOL_NAME" "$INSTALL_DIR/$TOOL_NAME"

echo "Installed $TOOL_NAME $VERSION to $INSTALL_DIR/$TOOL_NAME"
