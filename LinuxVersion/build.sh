#!/usr/bin/env bash
set -euo pipefail

# The repository root: this script lives in LinuxVersion/, the shared source in src/.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_LIB="$ROOT/build/lib"
mkdir -p "$BUILD_LIB" "$ROOT/bin" "$ROOT/build"

# Lazbuild's GTK3 widgetset needs unversioned development names at link time.
# Some distributions install only the versioned runtime libraries.
link_runtime() {
  local short="$1"
  local versioned="$2"
  local target
  target="$(ldconfig -p 2>/dev/null | awk -v n="$versioned" '$1 == n { print $NF; exit }')"
  if [[ -n "$target" ]]; then
    ln -sf "$target" "$BUILD_LIB/lib${short}.so"
  fi
}

link_runtime "gtk-3"             "libgtk-3.so.0"
link_runtime "gdk-3"             "libgdk-3.so.0"
link_runtime "cairo-gobject"     "libcairo-gobject.so.2"
link_runtime "cairo"             "libcairo.so.2"
link_runtime "pango-1.0"         "libpango-1.0.so.0"
link_runtime "gdk_pixbuf-2.0"    "libgdk_pixbuf-2.0.so.0"
link_runtime "atk-1.0"           "libatk-1.0.so.0"
link_runtime "harfbuzz"          "libharfbuzz.so.0"
link_runtime "harfbuzz-gobject"  "libharfbuzz-gobject.so.0"
link_runtime "pangocairo-1.0"    "libpangocairo-1.0.so.0"

mkdir -p "$ROOT/build/askpass"
fpc -O2 -FU"$ROOT/build/askpass" -FE"$ROOT/bin" -o"$ROOT/bin/sd-askpass" "$ROOT/src/sd-askpass.lpr"

LAZARUS_DIR="${LAZARUS_DIR:-/usr/share/lazarus/5.0.0}"
lazbuild --lazarusdir="$LAZARUS_DIR" --ws=gtk3 "$ROOT/src/sdtransfer.lpi"

# The Lazarus project keeps debug info for the IDE; the committed deliverable
# does not need it (it is ~36 MB with it, a few MB without).
if command -v strip >/dev/null 2>&1; then
  strip "$ROOT/bin/sd-transfer" "$ROOT/bin/sd-askpass"
fi
