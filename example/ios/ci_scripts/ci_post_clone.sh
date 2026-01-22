#!/bin/sh

set -e

echo "Navigating back to the repository root path from the default ci_scripts location ..."
cd $CI_PRIMARY_REPOSITORY_PATH

echo "Installing CocoaPods..."
export HOMEBREW_NO_AUTO_UPDATE=1
brew install cocoapods

echo "CocoaPods installed, updating repo..."
pod repo update

echo "Running Makefile targets for iOS..."
PLATFORM=ios

make ci-flutter-git-setup

export PATH="$PATH:$HOME/flutter/bin"

make ci-flutter-deps PLATFORM=$PLATFORM

make codegen

make ci-build-ios ENV_FILE=$ENV_FILE BUILD_NUMBER=$CI_BUILD_NUMBER

echo "CI build for iOS completed successfully."

exit 0
