#!/bin/bash
set -e

echo "Installing pre-commit hook..."
mkdir -p .git/hooks

cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh

# Run markdown linting
make lint
if [ $? -ne 0 ]; then
    echo "Error: Markdown linting failed. Please fix the issues before committing."
    exit 1
fi

# Do not allow committing when `specs/.current` directory exists, recommend the
# user to rename it to a feature name (recommended formats:
# `<task-number>-<feature-name>`)
if [ -d "specs/.current" ]; then
    echo "Error: Committing when \`specs/.current\` directory exists is not allowed."
    echo "Please rename the directory to a feature name (recommended formats: \`<task-number>-<feature-name>\`)."
    exit 1
fi
EOF

chmod +x .git/hooks/pre-commit
echo "Pre-commit hook installed successfully."
