#!/bin/bash
# Update version numbers for Delicious Island
# Usage: ./scripts/update-version.sh <version>
# Example: ./scripts/update-version.sh 0.2.0

set -e

VERSION=$1

if [ -z "$VERSION" ]; then
    echo "Error: Version argument required"
    echo "Usage: $0 <version>"
    exit 1
fi

echo "Updating version to: $VERSION"

PROJECT_FILE="DeliciousIsland.xcodeproj/project.pbxproj"

# Update MARKETING_VERSION in Xcode project
sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $VERSION;/g" "$PROJECT_FILE"

# Calculate build number from version (major * 10000 + minor * 100 + patch)
# For example: 0.2.1 -> 201, 1.0.0 -> 10000
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
BUILD_NUMBER=$((MAJOR * 10000 + MINOR * 100 + ${PATCH:-0}))

# Update CURRENT_PROJECT_VERSION (build number)
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PROJECT_FILE"

echo "Updated $PROJECT_FILE:"
echo "  MARKETING_VERSION = $VERSION"
echo "  CURRENT_PROJECT_VERSION = $BUILD_NUMBER"

# Update package.json version
if [ -f "package.json" ]; then
    npm version "$VERSION" --no-git-tag-version --allow-same-version
    echo "Updated package.json to version $VERSION"
fi

echo "Version update complete!"
