# Grey's Simple Slideshow

Plasma 6 wallpaper plugin that scans **all** configured folders (recursively),
picks an image, and shows a **different file on each screen**.  This behaves
similarly to the default Slideshow plugin but skips the initial file scan
during startup.  Only needed if you have dozens to hundreds of thousands of
images to pick from (which I do).


## Features

- Any number of folders; they are merged into one pool
- Recursive walk (`os.walk`), skipping hidden and VCS directories
- Unique file per screen via a locked claim file in `~/.cache/org.grey.simpleslideshow/claims.json`
- Picker is a Nim binary (`contents/code/pick.nim`); `install.sh` compiles it and the wallpaper falls back to `pick.py` if the binary is missing
- Optional interval; `0` means pick on load and when you choose **Next Wallpaper**
- Positioning: crop, stretch, contain, center, tile
- Crossfade between slides (same timing as Plasma Slideshow)
- Desktop context actions: next wallpaper, open current file

## Install

```bash
./install.sh
```

Then:

1. Right-click the desktop → **Configure Desktop and Wallpaper…**
2. Select the screen you want (Plasma 6 wallpaper dialog is per output)
3. Wallpaper type: **Grey's Simple Slideshow**
4. Add folders, set interval / positioning, Apply
5. Repeat for the other screen — do **not** use “Apply to all screens” if you
   want different images

If the type does not appear, restart the shell:

```bash
systemctl --user restart plasma-plasmashell
```

Uninstall:

```bash
kpackagetool6 --type Plasma/Wallpaper --remove org.grey.simpleslideshow
```


## Layout

```
package/
  metadata.json
  contents/
    config/main.xml
    ui/main.qml
    ui/config.qml
    code/pick.nim
    code/pick.py
```

`install.sh` runs `nim c -d:release` on `pick.nim`. The QML wallpaper invokes
that binary (or `python3 pick.py` if it is not executable).
