#!/bin/bash
# Başka Mac'lere kolayca indirip kurmak için DMG ve ZIP dağıtım paketlerini üretir.
set -euo pipefail
cd "$(dirname "$0")"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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
"$LSREGISTER" -u "$(pwd)/$STAGE/Ataç.app" 2>/dev/null || true
rm -rf "$STAGE"

# Dağıtım arşivleri üretildikten sonra geçici .app paketini kaldır ki Spotlight'ta çift görünmesin
"$LSREGISTER" -u "$(pwd)/build/Ataç.app" 2>/dev/null || true
rm -rf "build/Ataç.app"
"$LSREGISTER" -gc 2>/dev/null || true

echo "Hazır:"
echo "  ZIP: $(pwd)/$ZIP_OUT"
echo "  DMG: $(pwd)/$DMG_OUT"
