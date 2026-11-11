#!/bin/bash
# Clean build cache, DerivedData, and temporary build logs

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "Cleaning Xcode DerivedData for Navigy..."
rm -rf ~/Library/Developer/Xcode/DerivedData/Navigy-*

echo "Cleaning local build directory..."
rm -rf "$PROJECT_DIR/build"
rm -f /tmp/openclip.log

echo "Clean complete."
