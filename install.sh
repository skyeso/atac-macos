#!/bin/bash
# Ataç'ı derler ve çakışma olmadan yalnızca /Applications/Ataç.app olarak kurar.
set -euo pipefail
cd "$(dirname "$0")"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

./build.sh

echo "Uygulamalar klasörüne kopyalanıyor..."
killall Atac 2>/dev/null || true

# Önceden silinmiş dist/Ataç.app kaydı LaunchServices'ta kaldıysa geçici paketle kaydını düşür (-u mevcut yol ister)
mkdir -p "$(pwd)/dist"
ditto "build/Ataç.app" "$(pwd)/dist/Ataç.app"
"$LSREGISTER" -u "$(pwd)/dist/Ataç.app" 2>/dev/null || true
rm -rf "$(pwd)/dist"

rm -rf "/Applications/Ataç.app"
ditto "build/Ataç.app" "/Applications/Ataç.app"
xattr -cr "/Applications/Ataç.app" 2>/dev/null || true

# Geçici build/Ataç.app kaydını silmeden önce LaunchServices'tan düşür, ardından klasörü temizle
"$LSREGISTER" -u "$(pwd)/build/Ataç.app" 2>/dev/null || true
rm -rf "build/Ataç.app"

# Yalnızca resmi /Applications/Ataç.app kaydını tut ve eski ölü kayıtları sıkıştır
"$LSREGISTER" -gc 2>/dev/null || true
"$LSREGISTER" -f "/Applications/Ataç.app" 2>/dev/null || true

echo "Kurulum tamamlandı: /Applications/Ataç.app"
open "/Applications/Ataç.app"
