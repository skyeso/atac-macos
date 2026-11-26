#!/bin/bash
# Ataç'ı derler ve doğrudan /Applications (Uygulamalar) klasörüne kurar.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

echo "Uygulamalar klasörüne kopyalanıyor..."
killall Atac 2>/dev/null || true
rm -rf "/Applications/Ataç.app"
ditto "build/Ataç.app" "/Applications/Ataç.app"
xattr -cr "/Applications/Ataç.app" 2>/dev/null || true

echo "Kurulum tamamlandı: /Applications/Ataç.app"
open "/Applications/Ataç.app"
