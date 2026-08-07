#!/bin/bash
# Regenerates Resources/enru.icns from Sources/enru/IconArtwork.swift.
# Only needed when the artwork changes — the .icns is committed.
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p Resources
TOOL="$(mktemp -d)/make-icon"

# The artwork sources are compiled in alongside the generator so the icon file and the
# menu-bar item can never drift apart.
swiftc -O -o "${TOOL}" \
  Scripts/make-icon.swift \
  Sources/enru/IconArtwork.swift \
  Sources/enru/Wordmark.swift \
  Sources/enru/SVGPath.swift

"${TOOL}"
