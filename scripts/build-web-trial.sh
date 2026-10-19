#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn "$@"
python3 scripts/generate-web-cache.py
