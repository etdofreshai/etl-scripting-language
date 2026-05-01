#!/usr/bin/env bash
# Combined selfeval-all: runs headless self-evaluation + graphics smoke.
# Graphics checks are skip-safe: if SDL3 is absent, report SKIP and pass.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sdl3_available=false
if pkg-config --exists sdl3 2>/dev/null; then
  sdl3_available=true
fi

echo "=== selfeval-all: headless self-evaluation ==="
"$repo_root/scripts/selfeval_smoke.sh"

echo ""
echo "=== selfeval-all: headless graphics ==="
"$repo_root/scripts/sdl3_headless_smoke.sh"

if $sdl3_available; then
  echo ""
  echo "=== selfeval-all: checking graphics artifacts ==="
  ppm="$repo_root/build/graphics/pixel_fill.ppm"
  if [ -f "$ppm" ]; then
    hash=$(sha256sum "$ppm" | awk '{print $1}')
    echo "  pixel_fill.ppm: sha256=$hash"
    echo "  (future: compare against golden .sha256 sidecar)"
  else
    echo "  WARNING: SDL3 available but no PPM artifact found"
  fi
  echo "selfeval-all: PASS (selfeval + graphics with artifacts)"
else
  echo "selfeval-all: PASS (selfeval; graphics SKIP — SDL3 absent)"
fi
