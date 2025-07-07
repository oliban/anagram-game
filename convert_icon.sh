#!/bin/zsh

#
#  convert_icon.sh
#  Anagram Game
#
#  Created by Gemini on 2025-07-07.
#
#  This script converts an SVG icon to the 1024x1024 PNG format required
#  for the Xcode project's App Icon.
#
#  Usage:
#  ./convert_icon.sh <path_to_your_svg_file>
#
#  Dependency: ImageMagick
#  Install with Homebrew: brew install imagemagick
#

# --- Configuration ---
OUTPUT_DIR="Resources/Assets.xcassets/AppIcon.appiconset"
OUTPUT_FILENAME="icon_1024x1024.png"
OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_FILENAME"
OUTPUT_SIZE="1024x1024"

# --- Main Script ---

# Check for ImageMagick dependency
if ! command -v convert &> /dev/null
then
    echo "❌ Error: ImageMagick is not installed."
    echo "This script requires ImageMagick to convert SVG to PNG."
    echo "Please install it, for example using Homebrew:"
    echo "brew install imagemagick"
    exit 1
fi

# Check for input file argument
if [ -z "$1" ]; then
    echo "❌ Error: No input SVG file specified."
    echo "Usage: $0 <path_to_your_svg_file>"
    exit 1
fi

INPUT_SVG="$1"

# Check if input file exists
if [ ! -f "$INPUT_SVG" ]; then
    echo "❌ Error: Input file not found at '$INPUT_SVG'"
    exit 1
fi

echo "🎨 Converting '$INPUT_SVG' to '$OUTPUT_PATH'..."

# Create the output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Use ImageMagick to convert the SVG to PNG with a transparent background
convert -background none "$INPUT_SVG" -resize "$OUTPUT_SIZE" "$OUTPUT_PATH"

# Check if the conversion was successful
if [ $? -eq 0 ]; then
    echo "✅ Successfully created app icon at '$OUTPUT_PATH'"
else
    echo "❌ Error: ImageMagick conversion failed."
    exit 1
fi 