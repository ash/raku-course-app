#!/bin/sh
# Render the App Store header and search-results artwork from hero.html.
#
#   universal-5244x2950.png  the 16:9 "universal" asset (PNG only), for both
#   header-3840x1646.png     the 21:9 product page header: the middle band
#   search-3840x2560.png     the 3:2 search results image: the middle column
#
# All three are opaque: App Store Connect refuses alpha channels.
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=5244,2950 --screenshot="$PWD/raw.png" "file://$PWD/hero.html" 2>/dev/null
flat="-background #0e0d12 -alpha remove -alpha off -colorspace sRGB -density 72"
magick raw.png -crop 5244x2950+0+0 +repage $flat PNG24:universal-5244x2950.png
# 21:9 of 5244 wide is 2247 high, centred; 3:2 of 2950 high is 4425 wide, centred
magick universal-5244x2950.png -crop 5244x2247+0+351 +repage -resize 3840x1646! $flat PNG24:header-3840x1646.png
magick universal-5244x2950.png -crop 4425x2950+409+0 +repage -resize 3840x2560! $flat PNG24:search-3840x2560.png
rm -f raw.png
magick identify -format '%f %wx%h %[channels]\n' universal-5244x2950.png header-3840x1646.png search-3840x2560.png
