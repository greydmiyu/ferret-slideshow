#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PKG="$ROOT/package"
PLUGIN_ID="org.grey.simpleslideshow"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/wallpapers/$PLUGIN_ID"
PICK_SRC="$PKG/contents/code/pick.nim"
PICK_BIN="$PKG/contents/code/pick"

if command -v nim >/dev/null 2>&1; then
    nim c -d:release --opt:size -o:"$PICK_BIN" "$PICK_SRC"
else
    echo "nim not found; wallpaper picker will use pick.py" >&2
fi

if command -v kpackagetool6 >/dev/null 2>&1; then
    if kpackagetool6 --type Plasma/Wallpaper --show "$PLUGIN_ID" >/dev/null 2>&1; then
        kpackagetool6 --type Plasma/Wallpaper --upgrade "$PKG"
    else
        kpackagetool6 --type Plasma/Wallpaper --install "$PKG"
    fi
else
    mkdir -p "$DEST"
    cp -a "$PKG/." "$DEST/"
    echo "Installed by copy to $DEST (kpackagetool6 not found)"
fi

echo "Plugin installed as $PLUGIN_ID"
echo "Right-click the desktop → Configure Desktop and Wallpaper → Wallpaper type: Grey's Simple Slideshow"
echo "Repeat per screen; do not use Apply to all screens if you want different images."
echo "You may need to restart plasmashell: systemctl --user restart plasma-plasmashell"