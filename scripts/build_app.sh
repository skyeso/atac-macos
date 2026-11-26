#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
mkdir -p dist
rm -rf "dist/Ataç.app"
ditto "build/Ataç.app" "dist/Ataç.app"
