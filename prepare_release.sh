#!/bin/bash

set -e

# Check if version argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

NEW_VERSION="$1"
CURRENT_DATE=$(date +"%Y-%m-%d")
CURRENT_YEAR=$(date +"%Y")
PATCH_VERSION="${NEW_VERSION##*.}"
UPDATE_RELEASE_DOCS="${SHAPESCRIPT_UPDATE_RELEASE_DOCS:-}"
if [ -z "$UPDATE_RELEASE_DOCS" ]; then
    if [ "$PATCH_VERSION" = "0" ]; then
        UPDATE_RELEASE_DOCS=1
    else
        UPDATE_RELEASE_DOCS=auto
    fi
fi

echo "Preparing release for version $NEW_VERSION..."

# Validate version format (basic check for semantic versioning)
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in format X.Y.Z"
    exit 1
fi

# 1. Update CHANGELOG.md
echo "Updating CHANGELOG.md..."
# Create a temporary file for the new changelog content
TEMP_CHANGELOG=$(mktemp)

# Add new version entry at the top after the header
{
    echo "# Change Log"
    echo ""
    echo "## [$NEW_VERSION](https://github.com/nicklockwood/ShapeScript/releases/tag/$NEW_VERSION) ($CURRENT_DATE)"
    echo ""
    echo "- TODO"
    echo ""
    # Skip the first two lines (header) and add the rest
    tail -n +3 CHANGELOG.md
} > "$TEMP_CHANGELOG"

# Replace the original file
if ! grep -q "tag/$NEW_VERSION)" CHANGELOG.md; then
    mv "$TEMP_CHANGELOG" CHANGELOG.md
fi

# 2. Update version in README.md
echo "Updating README.md..."
sed -i '' "s/'~> [^\']*'/'~> $NEW_VERSION'/" README.md
sed -i '' "s/\" ~> [^ \n]*/\" ~> $NEW_VERSION/" README.md
sed -i '' "s/from: \"[^\"]*\"/from: \"$NEW_VERSION\"/" README.md

# 3. Update version in ShapeScript/Interpreter.swift
echo "Updating ShapeScript/Interpreter.swift..."
sed -i '' "s/public let version: String = \"[^\"]*\"/public let version: String = \"$NEW_VERSION\"/" ShapeScript/Interpreter.swift
sed -i '' "s/Copyright (c) 2023\\( *- *[0-9][0-9][0-9][0-9]\\)\\{0,1\\} Nick Lockwood/Copyright (c) 2023-$CURRENT_YEAR Nick Lockwood/" Viewer/CLI/CLI.swift

# 4. Update version in ShapeScript.xcodeproj
echo "Updating ShapeScript.xcodeproj..."
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $NEW_VERSION/" ShapeScript.xcodeproj/project.pbxproj
sed -i '' "s/Copyright © 2018\\( *- *[0-9][0-9][0-9][0-9]\\)\\{0,1\\} Nick Lockwood\\. All rights reserved\\./Copyright © 2018-$CURRENT_YEAR Nick Lockwood. All rights reserved./" ShapeScript.xcodeproj/project.pbxproj

# 5. Ensure docs version folder exists
echo "Checking docs version folder..."
DOCS_VERSION_PATH="docs/$NEW_VERSION"
if [ -e "$DOCS_VERSION_PATH" ] || [ -L "$DOCS_VERSION_PATH" ]; then
    echo "Docs entry already exists at $DOCS_VERSION_PATH"
else
    LATEST_DOCS_VERSION=$(find docs -mindepth 1 -maxdepth 1 -type d \
        -exec basename {} \; | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)

    if [ -z "$LATEST_DOCS_VERSION" ]; then
        echo "Error: No existing non-symlink docs version folders found in docs/."
        exit 1
    fi

    (cd docs && ln -s "$LATEST_DOCS_VERSION" "$NEW_VERSION")
    echo "Created docs symlink: $DOCS_VERSION_PATH -> $LATEST_DOCS_VERSION"
fi

if [ "$UPDATE_RELEASE_DOCS" = "auto" ]; then
    echo "Checking for release documentation changes..."
    if ! SHAPESCRIPT_UPDATE_RELEASE_DOCS=1 swift test --filter MetadataTests/testExportHelp; then
        echo "Error: Failed to validate or update release documentation."
        exit 1
    fi
    UPDATE_RELEASE_DOCS=0
fi

# 7. Run tests
echo "Running tests..."
if ! SHAPESCRIPT_UPDATE_RELEASE_DOCS="$UPDATE_RELEASE_DOCS" swift test --parallel --num-workers 10; then
    echo "Error: Tests failed. Please fix the issues before proceeding."
    if [ "$UPDATE_RELEASE_DOCS" != "1" ]; then
        echo "If this patch release intentionally changes docs, rerun with SHAPESCRIPT_UPDATE_RELEASE_DOCS=1."
    fi
    exit 1
fi

echo "Tests passed successfully."

# 8. Regenerate and validate bundled iOS Viewer documentation
echo "Regenerating iOS Viewer documentation..."
swift run helpbuilder --ios-viewer --validate-ios-output

echo ""
echo "✅ Release preparation completed successfully for version $NEW_VERSION!"
echo ""
echo "Remaining steps to be completed manually:"
echo "   - Fill out CHANGELOG.md"
echo "   - Commit to develop and main branches"
echo "   - Create release at https://github.com/nicklockwood/ShapeScript/releases"
echo "   - Update Cocoapod with 'pod trunk push --allow-warnings'"
echo ""
