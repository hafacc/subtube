#!/bin/sh
# Regenerate both apps' AppIcon PNGs from design/icons/sub-play-centred.svg:
# the logo's box at 84.375% of an ink tile, with all of the logo, tower and
# bubbles included, centred. The 16 pt files are made from
# sub-play-centred-small.svg, which has one large bubble. iOS gets a
# full-bleed square (the system masks it); macOS gets the 824 pt rounded
# tile with a shadow on the 1024 canvas.
# Needs rsvg-convert and sips. Run from anywhere.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
icons="$here/../design/icons"
out="$here/App/Resources/Assets.xcassets/AppIcon.appiconset"
work=$(mktemp -d)
trap 'rm -r "$work"' EXIT

tile() { # logo size inset radius shadow(0/1)
  paths=$(sed -e 's/^<svg[^>]*>//' -e 's/<\/svg>$//' "$icons/$1.svg"); shift
  t=$(echo "$1 - 2 * $2" | bc -l); glyph=$(echo "$t * 0.84375" | bc -l)
  offset=$(echo "$2 + ($t - $glyph) / 2" | bc -l); scale=$(echo "$glyph / 24" | bc -l)
  defs=""; filter=""
  if [ "$4" = 1 ]; then
    defs="<defs><filter id=\"s\" x=\"-20%\" y=\"-20%\" width=\"140%\" height=\"140%\"><feDropShadow dx=\"0\" dy=\"$(echo "$1 * 0.01" | bc -l)\" stdDeviation=\"$(echo "$1 * 0.012" | bc -l)\" flood-color=\"#000\" flood-opacity=\"0.3\"/></filter></defs>"
    filter=' filter="url(#s)"'
  fi
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s">%s<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="#1B1E24"%s/><g transform="translate(%s %s) scale(%s)">%s</g></svg>' \
    "$1" "$1" "$1" "$1" "$defs" "$2" "$2" "$t" "$t" "$3" "$filter" "$offset" "$offset" "$scale" "$paths"
}

tile sub-play-centred 1024 0 0 0 > "$work/ios.svg"
rsvg-convert -w 1024 -h 1024 "$work/ios.svg" -o "$work/ios.png"
# the App Store refuses an iOS icon with an alpha channel
sips -s format jpeg -s formatOptions 100 "$work/ios.png" --out "$work/ios.jpg" > /dev/null
sips -s format png "$work/ios.jpg" --out "$out/ios-1024.png" > /dev/null

tile sub-play-centred 1024 100 185.4 1 > "$work/mac.svg"
tile sub-play-centred-small 1024 100 185.4 1 > "$work/mac-small.svg"
for size in 16 32 128 256 512; do
  if [ $size = 16 ]; then source="$work/mac-small.svg"; else source="$work/mac.svg"; fi
  for scale in 1 2; do
    px=$((size * scale))
    rsvg-convert -w $px -h $px "$source" -o "$out/mac-$size@${scale}x.png"
  done
done
