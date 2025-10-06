#!/bin/bash

# iOS App Icon Generator
# Generates all required app icon sizes from a 1024x1024 source image

set -e

SOURCE_IMAGE="$1"
OUTPUT_DIR="${2:-./BooksTracker/Assets.xcassets/AppIcon.appiconset}"

if [ -z "$SOURCE_IMAGE" ]; then
    echo "Usage: $0 <source_image_path> [output_directory]"
    echo "Example: $0 ~/Desktop/app-icon.png"
    exit 1
fi

if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "Error: Source image not found: $SOURCE_IMAGE"
    exit 1
fi

echo "📱 Generating iOS App Icons from: $SOURCE_IMAGE"
echo "📂 Output directory: $OUTPUT_DIR"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# iOS App Icon sizes (iOS 18+, including iPad)
# Format: filename:size
declare -a SIZES=(
    "icon-1024.png:1024"      # App Store
    "icon-60@2x.png:120"      # iPhone App iOS 7-13 (60pt @2x)
    "icon-60@3x.png:180"      # iPhone App iOS 7-13 (60pt @3x)
    "icon-76.png:76"          # iPad App iOS 7-13 (76pt @1x)
    "icon-76@2x.png:152"      # iPad App iOS 7-13 (76pt @2x)
    "icon-83.5@2x.png:167"    # iPad Pro App iOS 9-13 (83.5pt @2x)
    "icon-20.png:20"          # iPad Notifications iOS 7-13 (20pt @1x)
    "icon-20@2x.png:40"       # iPhone/iPad Notifications iOS 7-13 (20pt @2x)
    "icon-20@3x.png:60"       # iPhone Notifications iOS 7-13 (20pt @3x)
    "icon-29.png:29"          # iPad Settings iOS 7-13 (29pt @1x)
    "icon-29@2x.png:58"       # iPhone/iPad Settings iOS 7-13 (29pt @2x)
    "icon-29@3x.png:87"       # iPhone Settings iOS 7-13 (29pt @3x)
    "icon-40.png:40"          # iPad Spotlight iOS 7-13 (40pt @1x)
    "icon-40@2x.png:80"       # iPhone/iPad Spotlight iOS 7-13 (40pt @2x)
    "icon-40@3x.png:120"      # iPhone Spotlight iOS 7-13 (40pt @3x)
)

# Generate each size using sips (built-in macOS tool)
for size_spec in "${SIZES[@]}"; do
    filename="${size_spec%%:*}"
    size="${size_spec##*:}"
    output_path="$OUTPUT_DIR/$filename"

    echo "  Generating $filename (${size}x${size}px)..."
    sips -z $size $size "$SOURCE_IMAGE" --out "$output_path" > /dev/null 2>&1
done

# Generate Contents.json for Xcode Asset Catalog
cat > "$OUTPUT_DIR/Contents.json" <<EOF
{
  "images" : [
    {
      "filename" : "icon-20@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-20@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-29@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-29@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-40@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-40@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-60@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "60x60"
    },
    {
      "filename" : "icon-60@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "60x60"
    },
    {
      "filename" : "icon-20.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-20@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-29.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-29@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-40.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-40@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-76.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "76x76"
    },
    {
      "filename" : "icon-76@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "76x76"
    },
    {
      "filename" : "icon-83.5@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "83.5x83.5"
    },
    {
      "filename" : "icon-1024.png",
      "idiom" : "ios-marketing",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo ""
echo "✅ Successfully generated all app icon sizes!"
echo "📍 Location: $OUTPUT_DIR"
echo ""
echo "📋 Generated files:"
ls -lh "$OUTPUT_DIR"/*.png 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
echo ""
echo "🎨 Next steps:"
echo "  1. Open BooksTracker.xcworkspace in Xcode"
echo "  2. Navigate to Assets.xcassets → AppIcon"
echo "  3. Icons should automatically appear!"
echo "  4. Build and run to see your new app icon 🚀"
