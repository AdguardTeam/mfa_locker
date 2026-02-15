#!/bin/bash
set -e

CHANGELOG="CHANGELOG.md"
WORKFLOWS_DIR="templates/workflows"

# Extract the latest released version from CHANGELOG.md (first ## [vX.Y.Z] after [Unreleased])
CHANGELOG_VERSION=$(grep -E '^\#\# \[v[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" | head -1 | sed -E 's/.*\[(v[0-9]+\.[0-9]+\.[0-9]+)\].*/\1/')

if [ -z "$CHANGELOG_VERSION" ]; then
    echo "ERROR: Could not find a released version in $CHANGELOG"
    exit 1
fi

echo "CHANGELOG version: $CHANGELOG_VERSION"

# Check each workflow file in templates/workflows/
ERRORS=0
for workflow in "$WORKFLOWS_DIR"/*.md; do
    if [ ! -f "$workflow" ]; then
        continue
    fi
    
    # Extract version from the description line in YAML frontmatter
    WORKFLOW_VERSION=$(grep -E '^description:.*\(v[0-9]+\.[0-9]+\.[0-9]+\)' "$workflow" | sed -E 's/.*\((v[0-9]+\.[0-9]+\.[0-9]+)\).*/\1/')
    
    if [ -z "$WORKFLOW_VERSION" ]; then
        echo "ERROR: $workflow has no version in description"
        ERRORS=$((ERRORS + 1))
    elif [ "$WORKFLOW_VERSION" != "$CHANGELOG_VERSION" ]; then
        echo "ERROR: $workflow has version $WORKFLOW_VERSION, expected $CHANGELOG_VERSION"
        ERRORS=$((ERRORS + 1))
    else
        echo "OK: $workflow ($WORKFLOW_VERSION)"
    fi
done

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "Version verification FAILED: $ERRORS error(s) found"
    exit 1
fi

echo ""
echo "Version verification PASSED: all workflows match $CHANGELOG_VERSION"
