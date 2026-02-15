#!/bin/bash
set -e

echo "Syncing workflows to .windsurf/workflows..."
mkdir -p .windsurf/workflows
cp templates/workflows/*.md .windsurf/workflows/
echo "Workflows synced successfully."
