#!/bin/bash
# Ataç.app paketini oluşturur: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

EXEC="Atac"
OUT="build/Ataç.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

swift build --disable-sandbox -c release --product "$EXEC" \
    -Xswiftc -Osize \
    -Xlinker -dead_strip

mkdir -p Resources build
# Spotlight'ın derleme klasöründeki geçici Ataç.app kopyasını indekslemesini engelle
touch build/.metadata_never_index
rm -rf dist

if [ ! -f Resources/AppIcon.icns ]; then
  swift scripts/generate_icon.swift Resources/AppIcon.icns
fi

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp ".build/release/$EXEC" "$OUT/Contents/MacOS/$EXEC"
strip -x "$OUT/Contents/MacOS/$EXEC" 2>/dev/null || true
chmod +x "$OUT/Contents/MacOS/$EXEC"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$OUT"

# Geçici derleme çıktısının Spotlight / LaunchServices'ta ikinci bir "Ataç" olarak görünmesini engelle
"$LSREGISTER" -u "$(pwd)/$OUT" 2>/dev/null || true

echo "Hazır: $(pwd)/$OUT"
