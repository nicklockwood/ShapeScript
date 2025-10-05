#!/bin/bash

set -e

# Check if version argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

NEW_VERSION="$1"
CURRENT_DATE=$(date +"%Y-%m-%d")

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

# 3. Update version in ShapeScript.podspec.json
echo "Updating ShapeScript.podspec.json..."
sed -i '' "s/\"version\": \"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" ShapeScript.podspec.json
sed -i '' "s/\"tag\": \"[^\"]*\"/\"tag\": \"$NEW_VERSION\"/" ShapeScript.podspec.json

# 4. Update version in Sources/ShapeScript.swift
echo "Updating Sources/ShapeScript.swift..."
sed -i '' "s/public let version: String = \"[^\"]*\"/public let version: String = \"$NEW_VERSION\"/" ShapeScript/Interpreter.swift

# 5. Update version in ShapeScript.xcodeproj
echo "Updating ShapeScript.xcodeproj..."
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $NEW_VERSION/" ShapeScript.xcodeproj/project.pbxproj

# 6. Run tests
echo "Running tests..."
if ! swift test --parallel --num-workers 10; then
    echo "Error: Tests failed. Please fix the issues before proceeding."
    exit 1
fi

echo "Tests passed successfully."

echo ""
echo "✅ Release preparation completed successfully for version $NEW_VERSION!"
echo ""
echo "Remaining steps to be completed manually:"
echo "   - Fill out CHANGELOG.md"
echo "   - Commit to develop and main branches"
echo "   - Create release at https://github.com/nicklockwood/ShapeScript/releases"
echo "   - Update Cocoapod with 'pod trunk push --allow-warnings'"
echo ""
