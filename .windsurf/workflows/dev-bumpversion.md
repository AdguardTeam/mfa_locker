---
description: Bump version in all template workflows and update CHANGELOG.md (v1.0.0)
---

# Bump Version

This workflow updates the version number in all template workflow descriptions
and updates `CHANGELOG.md` to reflect the new release.

## Input

The workflow requires a version number as input (the `$ARGUMENTS` provided by
the user). The version must follow semantic versioning format (e.g., `1.2.0`).

If no version is provided, stop and report:

**ERROR: No version provided. Usage: `/dev-bumpversion 1.2.0`**

## Prerequisites

Before starting, verify:

1. `CHANGELOG.md` exists and has an `## [Unreleased]` section
2. Template workflow files exist in `templates/workflows/`
3. The `## [Unreleased]` section has content to release

If the Unreleased section is empty:

**ERROR: The `## [Unreleased]` section is empty. Add changelog entries before
bumping version.**

## Steps

### Phase 1: Validate Input

1. **Parse the version number**
   - Extract version from `$ARGUMENTS`
   - Validate it matches semantic versioning pattern: `X.Y.Z` where X, Y, Z are
     non-negative integers
   - If invalid, report error with correct format

2. **Check version is newer**
   - Read `CHANGELOG.md` to find the latest released version
   - Verify the new version is greater than the current version
   - If not, report error

### Phase 2: Update Template Workflows

1. **Find all template workflow files**
   - List files in `templates/workflows/`
   - Identify files with `.md` extension

2. **Update version in each workflow**
   For each workflow file:
   - Read the file
   - Find the `description:` line in the YAML frontmatter
   - Replace the version pattern `(vX.Y.Z)` with `(v$NEW_VERSION)`
   - If no version exists, append `(v$NEW_VERSION)` to the description
   - Write the updated file

### Phase 3: Update CHANGELOG.md

1. **Read the current CHANGELOG.md**
   - Parse the file structure
   - Identify the `## [Unreleased]` section and its content
   - Identify the version links at the bottom of the file

2. **Create new version section**
   - Get today's date in `YYYY-MM-DD` format
   - Create new section header: `## [v$NEW_VERSION] - YYYY-MM-DD`
   - Move all content from `## [Unreleased]` to the new version section
   - Leave `## [Unreleased]` empty (just the header)

3. **Update version links**
   - Add new version link at the bottom (before `[unreleased]` link)
   - Update the `[unreleased]` link to compare from the new version tag

### Phase 4: Sync Workflows

1. **Copy updated workflows to .windsurf/workflows/**
   - Run `make sync-windsurf` or manually copy files
   - Verify both locations have matching content

### Phase 5: Verification

1. **Run automated version verification**

   ```bash
   make verify-version
   ```

   This script checks that:
   - All template workflow descriptions contain the same version
   - The version matches the latest released version in `CHANGELOG.md`

   If verification fails, fix the inconsistencies before proceeding.

2. **Manual verification checklist**

   - [ ] `CHANGELOG.md` has new version section with today's date
   - [ ] `## [Unreleased]` section is empty (header only)
   - [ ] Version link added at bottom of `CHANGELOG.md`
   - [ ] `[unreleased]` link updated to compare from new tag
   - [ ] `.windsurf/workflows/` files match `templates/workflows/`
   - [ ] `make lint` passes

### Phase 6: Output

1. **Report completion status**
   - List all files modified
   - Show the new version section in CHANGELOG.md

2. **Print next steps for the user**

   ```text
   Version bump complete. Run the following commands:

   git add -A
   git commit -m "Bump version to v$NEW_VERSION"
   git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"
   git push origin master --tags
   ```

## Guidelines

- **Atomic changes**: All version updates should happen together
- **Validate first**: Check all prerequisites before making changes
- **Preserve content**: Never lose changelog entries during the move
- **Consistent format**: Use the same version format everywhere `(vX.Y.Z)`
- **Date accuracy**: Use the actual current date for the release
