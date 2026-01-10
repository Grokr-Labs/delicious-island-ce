#!/bin/bash
# Extract release notes for a specific version from CHANGELOG.md
# Usage: ./scripts/extract-release-notes.sh <version> [--html]
#
# Examples:
#   ./scripts/extract-release-notes.sh 0.2.0          # Output markdown
#   ./scripts/extract-release-notes.sh 0.2.0 --html   # Output HTML

set -e

VERSION=$1
FORMAT=${2:-"md"}

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> [--html]"
    echo "Example: $0 0.2.0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CHANGELOG="$PROJECT_DIR/CHANGELOG.md"

if [ ! -f "$CHANGELOG" ]; then
    echo "Error: CHANGELOG.md not found at $CHANGELOG"
    exit 1
fi

# Extract section between "## [VERSION]" and next "## [" or end of file
# Handle both [0.2.0] and [v0.2.0] formats
NOTES=$(sed -n "/^## \[v\?$VERSION\]/,/^## \[/p" "$CHANGELOG" | head -n -1 | tail -n +2)

if [ -z "$NOTES" ]; then
    echo "No release notes found for version $VERSION"
    exit 0
fi

if [ "$FORMAT" = "--html" ]; then
    # Convert markdown to basic HTML
    cat << 'HTMLHEAD'
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Release Notes</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      padding: 20px;
      max-width: 600px;
      line-height: 1.6;
      color: #333;
    }
    h2 { color: #d97756; margin-top: 1.5em; }
    h3 { color: #555; margin-top: 1.2em; }
    ul { padding-left: 20px; }
    li { margin: 8px 0; }
    code {
      background: #f4f4f4;
      padding: 2px 6px;
      border-radius: 3px;
      font-size: 0.9em;
    }
  </style>
</head>
<body>
HTMLHEAD

    # Convert markdown to HTML
    echo "$NOTES" | sed '
        s/^### \(.*\)/<h3>\1<\/h3>/
        s/^## \(.*\)/<h2>\1<\/h2>/
        s/^\* \(.*\)/<li>\1<\/li>/
        s/^- \(.*\)/<li>\1<\/li>/
        s/`\([^`]*\)`/<code>\1<\/code>/g
        s/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g
    ' | awk '
        BEGIN { in_list = 0 }
        /<li>/ {
            if (!in_list) { print "<ul>"; in_list = 1 }
            print
            next
        }
        {
            if (in_list) { print "</ul>"; in_list = 0 }
            print
        }
        END { if (in_list) print "</ul>" }
    '

    echo "</body></html>"
else
    # Output raw markdown
    echo "$NOTES"
fi
