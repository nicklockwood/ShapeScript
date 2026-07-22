#!/bin/bash

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

NEW_VERSION="$1"
CURRENT_DATE=$(date +"%Y-%m-%d")

echo "Preparing release for version $NEW_VERSION..."

if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in format X.Y.Z"
    exit 1
fi

echo "Updating CHANGELOG.md..."
TEMP_CHANGELOG=$(mktemp)

{
    echo "# Change Log"
    echo ""
    echo "## [$NEW_VERSION](https://github.com/nicklockwood/ContextMenu/releases/tag/$NEW_VERSION) ($CURRENT_DATE)"
    echo ""
    echo "- TODO"
    echo ""
    tail -n +3 CHANGELOG.md
} > "$TEMP_CHANGELOG"

if ! grep -q "tag/$NEW_VERSION)" CHANGELOG.md; then
    mv "$TEMP_CHANGELOG" CHANGELOG.md
fi

echo "Updating README.md..."
sed -i '' "s/from: \"[^\"]*\"/from: \"$NEW_VERSION\"/" README.md

echo "Updating ContextMenu.xcodeproj..."
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $NEW_VERSION/" ContextMenu.xcodeproj/project.pbxproj

echo "Running tests..."
xcodebuild test \
    -project ContextMenu.xcodeproj \
    -scheme ContextMenu \
    -destination "platform=iOS Simulator,name=iPhone 16" \
    -derivedDataPath Build

echo "Tests passed successfully."

echo ""
echo "Release preparation completed successfully for version $NEW_VERSION."
echo ""
echo "Remaining steps:"
echo "   - Fill out CHANGELOG.md"
echo "   - Commit to develop and main branches"
echo "   - Create release at https://github.com/nicklockwood/ContextMenu/releases"
