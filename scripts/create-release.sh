#!/bin/bash
# Create a release: notarize, create DMG, sign for Sparkle, upload to GitHub, update appcast
#
# Usage:
#   ./scripts/create-release.sh           # Interactive mode (prompts for confirmation)
#   ./scripts/create-release.sh --ci      # CI mode (no prompts, for GitHub Actions)
#
set -e

# Parse arguments
CI_MODE=false
for arg in "$@"; do
    case $arg in
        --ci)
            CI_MODE=true
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
EXPORT_PATH="$BUILD_DIR/export"
RELEASE_DIR="$PROJECT_DIR/releases"
KEYS_DIR="$PROJECT_DIR/.sparkle-keys"
DOCS_DIR="$PROJECT_DIR/docs"

# GitHub repository (owner/repo format)
GITHUB_REPO="Grokr-Labs/delicious-island-pe"

APP_PATH="$EXPORT_PATH/Delicious Island.app"
APP_NAME="DeliciousIsland"
KEYCHAIN_PROFILE="DeliciousIsland"

echo "=== Creating Release ==="
echo ""

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at $APP_PATH"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

# Get version from app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")

echo "Version: $VERSION (build $BUILD)"
echo ""

mkdir -p "$RELEASE_DIR"

# ============================================
# Step 1: Notarize the app
# ============================================
echo "=== Step 1: Notarizing ==="

# Check if keychain profile exists
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null; then
    echo ""
    echo "No keychain profile found. Set up credentials with:"
    echo ""
    echo "  xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
    echo "      --apple-id \"your@email.com\" \\"
    echo "      --team-id \"2DKS5U9LV4\" \\"
    echo "      --password \"xxxx-xxxx-xxxx-xxxx\""
    echo ""
    echo "Create an app-specific password at: https://appleid.apple.com"
    echo ""
    if [ "$CI_MODE" = true ]; then
        echo "ERROR: Notarization credentials required in CI mode"
        exit 1
    fi
    read -p "Skip notarization for now? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    SKIP_NOTARIZATION=true
    echo "WARNING: Skipping notarization. Users will see Gatekeeper warnings!"
else
    # Create zip for notarization
    ZIP_PATH="$BUILD_DIR/$APP_NAME-$VERSION.zip"
    echo "Creating zip for notarization..."
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "Submitting for notarization..."
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"

    rm "$ZIP_PATH"
    echo "Notarization complete!"
fi

echo ""

# ============================================
# Step 2: Create DMG
# ============================================
echo "=== Step 2: Creating DMG ==="

DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"

# Remove existing DMG if present
if [ -f "$DMG_PATH" ]; then
    echo "Removing existing DMG..."
    rm -f "$DMG_PATH"
fi

# Check if create-dmg is available (prettier DMG)
if command -v create-dmg &> /dev/null; then
    echo "Using create-dmg for prettier output..."
    create-dmg \
        --volname "Delicious Island" \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "Delicious Island.app" 150 200 \
        --app-drop-link 450 200 \
        --hide-extension "Delicious Island.app" \
        "$DMG_PATH" \
        "$APP_PATH"
else
    echo "Using hdiutil (install create-dmg for prettier DMG: brew install create-dmg)"
    hdiutil create -volname "Delicious Island" \
        -srcfolder "$APP_PATH" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

echo "DMG created: $DMG_PATH"
echo ""

# ============================================
# Step 3: Notarize the DMG
# ============================================
if [ -z "$SKIP_NOTARIZATION" ]; then
    echo "=== Step 3: Notarizing DMG ==="

    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    xcrun stapler staple "$DMG_PATH"
    echo "DMG notarized!"
    echo ""
fi

# ============================================
# Step 4: Sign for Sparkle and generate appcast
# ============================================
echo "=== Step 4: Signing for Sparkle ==="

# Find Sparkle tools
SPARKLE_SIGN=""
GENERATE_APPCAST=""

POSSIBLE_PATHS=(
    "$HOME/Library/Developer/Xcode/DerivedData/DeliciousIsland-*/SourcePackages/artifacts/sparkle/Sparkle/bin"
)

for path_pattern in "${POSSIBLE_PATHS[@]}"; do
    for path in $path_pattern; do
        if [ -x "$path/sign_update" ]; then
            SPARKLE_SIGN="$path/sign_update"
            GENERATE_APPCAST="$path/generate_appcast"
            break 2
        fi
    done
done

if [ -z "$SPARKLE_SIGN" ]; then
    echo "WARNING: Could not find Sparkle tools."
    echo "Build the project in Xcode first to download Sparkle package."
    echo ""
    echo "Skipping Sparkle signing. You'll need to manually:"
    echo "1. Sign the DMG with sign_update"
    echo "2. Generate appcast with generate_appcast"
else
    # Check for private key
    if [ ! -f "$KEYS_DIR/eddsa_private_key" ]; then
        echo "WARNING: No private key found at $KEYS_DIR/eddsa_private_key"
        echo "Run ./scripts/generate-keys.sh first"
        echo ""
        echo "Skipping Sparkle signing."
    else
        # Generate signature
        echo "Signing DMG for Sparkle..."
        SIGNATURE=$("$SPARKLE_SIGN" --ed-key-file "$KEYS_DIR/eddsa_private_key" "$DMG_PATH")

        echo ""
        echo "Sparkle signature:"
        echo "$SIGNATURE"
        echo ""

        # Generate/update appcast
        echo "Generating appcast..."
        APPCAST_DIR="$RELEASE_DIR/appcast"
        mkdir -p "$APPCAST_DIR"

        # Copy DMG to appcast directory
        cp "$DMG_PATH" "$APPCAST_DIR/"

        # Generate appcast.xml
        "$GENERATE_APPCAST" --ed-key-file "$KEYS_DIR/eddsa_private_key" "$APPCAST_DIR"

        echo "Appcast generated at: $APPCAST_DIR/appcast.xml"
    fi
fi

echo ""

# ============================================
# Step 5: Create GitHub Release
# ============================================
echo "=== Step 5: Creating GitHub Release ==="

if ! command -v gh &> /dev/null; then
    echo "WARNING: gh CLI not found. Install with: brew install gh"
    echo "Skipping GitHub release."
else
    # Check if release already exists
    if gh release view "v$VERSION" --repo "$GITHUB_REPO" &>/dev/null; then
        echo "Release v$VERSION already exists. Updating..."
        gh release upload "v$VERSION" "$DMG_PATH" --repo "$GITHUB_REPO" --clobber
    else
        echo "Creating release v$VERSION..."
        gh release create "v$VERSION" "$DMG_PATH" \
            --repo "$GITHUB_REPO" \
            --title "Delicious Island v$VERSION" \
            --notes "## Delicious Island v$VERSION

### Installation
1. Download \`$APP_NAME-$VERSION.dmg\`
2. Open the DMG and drag Delicious Island to Applications
3. Launch Delicious Island from Applications

### Auto-updates
After installation, Delicious Island will automatically check for updates."
    fi

    GITHUB_DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$APP_NAME-$VERSION.dmg"
    echo "GitHub release created: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
    echo "Download URL: $GITHUB_DOWNLOAD_URL"
fi

echo ""

# ============================================
# Step 6: Update docs/appcast.xml for GitHub Pages
# ============================================
echo "=== Step 6: Updating Appcast ==="

if [ -f "$RELEASE_DIR/appcast/appcast.xml" ]; then
    # Copy appcast to docs/ for GitHub Pages
    mkdir -p "$DOCS_DIR"
    cp "$RELEASE_DIR/appcast/appcast.xml" "$DOCS_DIR/appcast.xml"

    # Update the download URL in appcast to point to GitHub releases
    if [ -n "$GITHUB_DOWNLOAD_URL" ]; then
        sed -i '' "s|url=\"[^\"]*$APP_NAME-$VERSION.dmg\"|url=\"$GITHUB_DOWNLOAD_URL\"|g" "$DOCS_DIR/appcast.xml"
        echo "Updated appcast.xml with GitHub download URL"
    fi

    # Generate release notes HTML if CHANGELOG.md exists
    if [ -f "$PROJECT_DIR/CHANGELOG.md" ]; then
        mkdir -p "$DOCS_DIR/notes"
        "$SCRIPT_DIR/extract-release-notes.sh" "$VERSION" --html > "$DOCS_DIR/notes/$VERSION.html" 2>/dev/null || true
        if [ -s "$DOCS_DIR/notes/$VERSION.html" ]; then
            echo "Generated release notes HTML"
        fi
    fi

    echo "Appcast updated at: $DOCS_DIR/appcast.xml"

    # Commit changes if not in CI mode (CI handles its own commits)
    if [ "$CI_MODE" = false ]; then
        cd "$PROJECT_DIR"
        git add docs/appcast.xml docs/notes/ 2>/dev/null || true
        if ! git diff --cached --quiet; then
            read -p "Commit appcast changes? (Y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                git commit -m "chore: update appcast for v$VERSION"
                echo "Committed appcast update"

                read -p "Push changes? (Y/n) " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    git push
                    echo "Pushed to remote!"
                fi
            fi
        else
            echo "No changes to commit"
        fi
    fi
else
    echo "Appcast not generated - skipping update"
fi

echo ""

echo "=== Release Complete ==="
echo ""
echo "Files created:"
echo "  - DMG: $DMG_PATH"
if [ -f "$RELEASE_DIR/appcast/appcast.xml" ]; then
    echo "  - Appcast (local): $RELEASE_DIR/appcast/appcast.xml"
fi
if [ -f "$DOCS_DIR/appcast.xml" ]; then
    echo "  - Appcast (docs): $DOCS_DIR/appcast.xml"
fi
if [ -n "$GITHUB_DOWNLOAD_URL" ]; then
    echo "  - GitHub Release: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
fi
echo ""
echo "Next steps:"
echo "  1. Push changes to trigger GitHub Pages update"
echo "  2. Verify appcast at: https://grokr-labs.github.io/delicious-island/appcast.xml"
