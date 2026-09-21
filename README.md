<div align="center">
  <img src="preview.png" alt="Retina Screenshot — true high-DPI capture for Omarchy" width="100%">

  <p><strong>Genuinely high-resolution region and window screenshots for Omarchy.</strong></p>

  <p>
    <a href="https://github.com/markey/omarchy-retina-screenshot/releases"><img src="https://img.shields.io/badge/version-1.1.4-f97360" alt="Version 1.1.4"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-f5b342" alt="MIT License"></a>
    <img src="https://img.shields.io/badge/Omarchy-4.x-22272e" alt="Omarchy 4.x">
    <img src="https://img.shields.io/badge/Hyprland-0.55%2B-58e1ff" alt="Hyprland 0.55 or newer">
  </p>
</div>

## What it does

Retina Screenshot lets you select a region inside any visible window, or select
a whole window, before moving its **entire workspace** to a temporary 2×
headless output. Wayland-native applications get a real high-DPI configure event
and can repaint text, icons, SVGs, browser content, and toolkit UI at the higher
buffer scale. The result is captured with `grim`, copied with `wl-copy`, and
saved to the normal Omarchy screenshot directory.

This is rendering, not interpolation. The script never mirrors the physical
display and does not upscale a normal screenshot afterward.

## Why the whole workspace moves

Removing one tiled window and inserting it again can change Hyprland's tiling
tree. Moving the workspace preserves tiled order, groups, floating geometry,
fullscreen state, and the target window's logical dimensions. Only the selected
region or selected window rectangle is captured. The workspace is returned
before the temporary output is destroyed.

## Requirements

- Omarchy 4.x / Hyprland with named headless outputs
- `hyprctl`, `grim`, `wl-copy`, `jq`, `flock`
- A Wayland-native target application for a guaranteed high-DPI repaint

The current implementation is live-tested on Omarchy 4.0.4 with Hyprland
0.56.2. It uses Hyprland's Lua monitor/dispatcher API on 0.55+ and retains a
legacy dispatcher fallback for older Hyprland configurations.

The script detects the focused monitor's physical size and scale. For example,
a 3440×1440 output at 1.25× has a 2752×1152 logical area, so v1 creates a
5504×2304 output at scale 2. A 1920×1080 output at scale 1 creates the familiar
3840×2160 output at scale 2.

## Install

From a published Git repository:

```bash
omarchy plugin add https://github.com/markey/omarchy-retina-screenshot.git --enable --yes
```

For local development:

```bash
mkdir -p ~/.config/omarchy/plugins
cp -a ./omarchy-retina-screenshot ~/.config/omarchy/plugins/mark.retina-screenshot
omarchy plugin validate ~/.config/omarchy/plugins/mark.retina-screenshot
omarchy plugin enable mark.retina-screenshot right
```

Left-clicking the bar camera opens Omarchy's frozen-screen region picker. The
pointer changes to the normal selection cursor; drag a rectangle entirely inside
the window you want. Right-clicking opens the save/clipboard options panel, with
separate **Select a region** and **Select a whole window** buttons.

## Uninstall

Remove the installed plugin and its bar entry with:

```bash
omarchy plugin remove mark.retina-screenshot --yes
```

Saved screenshots are ordinary image files and are not deleted when the plugin
is removed.

## Keyboard shortcut

The service exposes a plugin action:

```bash
omarchy-shell mark.retina-screenshot capture          # region picker
omarchy-shell mark.retina-screenshot captureRegion    # region picker
omarchy-shell mark.retina-screenshot captureWindow    # window picker
```

Or invoke the script directly:

```bash
~/.config/omarchy/plugins/mark.retina-screenshot/scripts/retina-screenshot
```

Add a user-owned binding to `~/.config/hypr/bindings.lua` only if you want it.
This example does **not** replace Omarchy's normal screenshot shortcut:

```lua
o.bind("SUPER + SHIFT + R", "Retina Screenshot", "omarchy-shell mark.retina-screenshot capture")
```

If you deliberately want `SUPER + SHIFT + S`, unbind or change the existing
Omarchy screenshot action first rather than creating a collision.

## Script usage

```text
retina-screenshot [--region|--window] [--scale 2] [--delay SECONDS]
                  [--copy|--no-copy] [--save|--no-save]
                  [--output-dir DIRECTORY] [--diagnose] [--debug]
```

Useful checks:

```bash
scripts/retina-screenshot --diagnose
RETINASHOT_DEBUG=1 scripts/retina-screenshot --delay 1.5
```

The save directory follows `OMARCHY_SCREENSHOT_DIR`, `XDG_PICTURES_DIR`, then
`~/Pictures`, matching Omarchy's screenshot command.

## Safety and cleanup

Before changing the compositor, the script records the focused window, monitor,
workspace, tiled/floating state, fullscreen state, and geometry. A single-instance
lock prevents overlapping captures. `EXIT`, `INT`, and `TERM` traps restore the
workspace, window details, and focus before removing the uniquely named headless
output. The reserved output name is `RETINA-SCREENSHOT`; using one stable name
also prevents runtime monitor rules from accumulating under per-process names.
The same cleanup runs when output configuration, repaint, `grim`, or
clipboard copying fails. Long-lived clipboard and notification helpers receive
no copy of the capture-lock descriptor, so they cannot block the next capture.
The picker also temporarily uses Omarchy's hardware-cursor setting so the live
selection cursor remains visible over the frozen desktop, restoring the user's
previous cursor mode on every exit path.
The picker keeps that frozen frame over the physical display while the workspace
visits the headless output, then removes it only after the original workspace,
window state, and focus have been restored. `grim` is restricted to the named
headless output, so the frozen cover is never part of the Retina capture.
Picker startup is deferred until the Shell has finished dispatching the bar or
panel click, preventing the new selection surface from inheriting a stale
pointer grab.

The picker always receives `/dev/null` on stdin so Quickshell's open process
pipe cannot make `slurp` wait forever for rectangle input. Picker descendants
do not inherit the capture lock, the picker has a 60-second deadline, the full
Shell action has a three-minute watchdog, and capture/clipboard/notification
helpers have their own short deadlines. Cancellation and signals terminate the
entire picker process group before restoring cursor and desktop state.

Pinned windows and special workspaces are rejected in v1 because moving them
safely without changing unrelated desktop state is not guaranteed.

## Accuracy notes

- Native Wayland Chromium/Electron, Qt, and GTK apps can react to the output's
  integer buffer scale and render real additional detail.
- XWayland has no general per-output HiDPI mechanism. The script warns but still
  captures; such a window may remain low-resolution or be compositor-scaled.
- Hyprland does not expose a universal "application finished repainting" event.
  v1 waits for stable compositor geometry, then uses a configurable one-second
  repaint delay. Increase `--delay` for a slow application.
- Region mode is the default. The selection must fit entirely inside one visible
  regular workspace window. Window mode uses Omarchy's highlighted window picker.
- Workspace, 3×, and supersampled-downsample modes are not implemented.

## Validate and test

```bash
omarchy plugin validate .
bash -n scripts/retina-screenshot tests/test-retina-screenshot.sh
tests/test-retina-screenshot.sh
```

The test harness mocks Hyprland and verifies region translation, selection of a
window other than the focused one, frozen-cover ordering and cleanup,
cancellation, successful cleanup, and cleanup after a forced `grim` failure.

Live verification on the test system produced:

- floating window: 900×650 logical → 1800×1300 PNG, identical state afterward
- tiled window: 2728×1102 logical → 5456×2204 PNG, identical state afterward
- no `RETINA-*` output remaining after either capture

## License

MIT
