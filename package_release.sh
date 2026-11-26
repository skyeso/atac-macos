#!/bin/bash
# Başka Mac'lere kolayca indirip kurmak için DMG ve ZIP dağıtım paketlerini üretir.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d "build/Ataç.app" ]; then
  ./build.sh
fi

VERSION="v0.1-alpha"
ZIP_OUT="build/Atac-${VERSION}-macOS.zip"
DMG_OUT="build/Atac-${VERSION}-macOS.dmg"
STAGE="build/dmg_stage"

rm -f "$ZIP_OUT" "$DMG_OUT"
ditto -c -k --keepParent "build/Ataç.app" "$ZIP_OUT"

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "build/Ataç.app" "$STAGE/Ataç.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Ataç" -srcfolder "$STAGE" -ov -format UDZO "$DMG_OUT" >/dev/null
rm -rf "$STAGE"

echo "Hazır:"
echo "  ZIP: $(pwd)/$ZIP_OUT"
echo "  DMG: $(pwd)/$DMG_OUT"
