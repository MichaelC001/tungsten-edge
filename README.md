<div align="center">

<img src="assets/icon.png" width="128" alt="Tungsten Edge" />

# Tungsten Edge

**A per-window taskbar for macOS — switch to any window in one click, Windows-style clarity without the clutter.**

English · [中文](README.zh-CN.md)

### [⬇ Download for macOS](https://tungstenedge.app)

Ready-to-run builds live on the [official website](https://tungstenedge.app). This repository holds the source.

</div>

---

## Demo

**Multi-window management**

<img src="assets/multi-window.gif" alt="Multi-window management" width="100%" />

<table>
  <tr>
    <td align="center"><b>App drawer &amp; launcher</b></td>
    <td align="center"><b>Drag to organize</b></td>
  </tr>
  <tr>
    <td><img src="assets/launcher.gif" alt="App drawer &amp; launcher" /></td>
    <td><img src="assets/drag-reorder.gif" alt="Drag to organize" /></td>
  </tr>
</table>

---

## What it is

Tungsten Edge puts a **per-window taskbar** at the bottom of your screen. Every open window gets its own card — just like a Windows taskbar — so you can switch directly to any window with a single click. No more hunting through stacked windows, no Mission Control, no extra gestures.

Unlike a plain Windows-style task switcher, single-window apps stay collapsed as compact icons, so the strip never gets cluttered. Multi-window apps (four Finder folders, multiple browser windows) expand into individual labeled cards. The result: the compactness of the macOS Dock combined with the per-window clarity of a Windows taskbar — without inheriting its problems.

## Features

- **Window-level taskbar** — one card per window; multi-window apps split into multiple cards; click to switch / minimize.
- **Smart native-tab merging** — apps where "tabs are windows" (Ghostty, Finder) keep a stable card while you switch tabs: it won't jump around or split.
- **Pinned messaging apps + badges** — messaging apps (WeChat, Feishu, …) get a persistent pinned entry and mirror the Dock's red unread badge.
- **App drawer** — stash rarely-used apps into a drawer on the right to keep the strip clean; pin favorites in the drawer to use it as a launcher.
- **Drag to organize** — reorder cards by dragging; drag a card into the drawer to stash it; drag it back out and it lands exactly where you drop it.
- **Menu bar controls** — the status menu controls launch at login, native Dock visibility and wake timing, Tungsten Edge wake timing, whether the shelf is shown, and the taskbar size.
- **Edge auto-hide** — Tungsten Edge can hide itself and wake from the bottom edge after the delay you choose; moving away hides it again after about 0.2s.
- **Frosted-glass look** — native-grade translucency that blends into the desktop.
- **Multi-display follow** — resting the pointer on another screen's bottom edge moves the taskbar there automatically.
- **Blink-free native fullscreen entry** — before a standard green-button or `Control-Command-F` fullscreen transition, Tungsten Edge moves its panels out of the transition snapshot. This is enabled by default and can be turned off in Settings.

> **Note:** the app's interface is currently **Chinese only**. An English/localized UI is planned but not yet available — see [Roadmap](#roadmap).

## Requirements

- macOS 12.0 (Monterey) or later
- Intel and Apple Silicon (universal binary)
- On first launch you'll be asked to grant **Accessibility** permission (used to read and manage windows; the app guides you through it).

### Global input observation

Entering a native fullscreen Space lets the system's transition snapshot catch the taskbar, which shows up as a one-frame blink. Removing it requires hiding the taskbar *before* your input reaches the target app, so Tungsten Edge observes global **left-click, key-down and trackpad gesture** events. It recognizes only these four:

- the standard window green button
- the exact `Control-Command-F` shortcut
- `Control-Left` / `Control-Right` (when switching into an adjacent fullscreen Space)
- a three-finger horizontal swipe (same case)

Ordinary input is not recorded, logged, modified, or sent anywhere. The listener is enabled by default; turn off **预测全屏切换，消除任务条闪烁** under **高级** in Settings to disable it completely.

macOS suppresses key events from global event taps while Secure Input is active, such as in a protected password field. During that time the keyboard shortcuts cannot be recognized in advance; green-button and trackpad-gesture detection are unaffected.

## Install

### Option 1 — download the installer (recommended)

1. Download the latest `.dmg` from the [official website](https://tungstenedge.app).
2. Open it and drag **Tungsten Edge** into your **Applications** folder.
3. **First launch needs to be allowed once** (this is an early, unsigned build, so macOS blocks it by default — it's not malware) — follow [First launch](#first-launch) below, then grant Accessibility permission.

### Option 2 — Homebrew (for technical users)

```bash
brew tap moonbai-studio/tungsten-edge
brew trust moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

> The `brew trust` step is required for any third-party tap. If the first launch is blocked by macOS, allow it as described in [First launch](#first-launch) below.

## First launch

Because this is an early build that isn't Apple-notarized yet, macOS blocks it the first time with a message like "cannot be opened because it is from an unidentified developer". **This isn't malware — it's macOS's default block for any unsigned app.** Allow it once and double-clicking works normally afterward. Pick the method for your macOS version:

### Method A — right-click to open (macOS 14 and earlier)

1. Open your **Applications** folder and find **Tungsten Edge**.
2. **Right-click its icon** (or Control-click it) and choose **Open** from the menu.
3. The dialog this time has an extra **Open** button — click it.
4. Done. Double-click works from now on.

> The trick is to go through **right-click → Open**, not a plain double-click — a plain double-click only gets blocked, with no allow button.

### Method B — allow it in System Settings (macOS 15 Sequoia and newer)

Newer macOS removed right-click-to-open, so do this instead:

1. **Double-click** Tungsten Edge once; when it's blocked, **click "Done"** to dismiss the prompt (this lets the system record the attempt).
2. Open **System Settings → Privacy & Security** and scroll down to the **Security** section.
3. You'll see a line saying "Tungsten Edge was blocked…" with an **"Open Anyway"** button next to it — click it.
4. Confirm once more (you may need your login password or Touch ID). Done — double-click works from now on.

### One more step after opening: grant Accessibility permission

Tungsten Edge needs **Accessibility** permission to read and manage your windows; it guides you through this on first run:

- Open **System Settings → Privacy & Security → Accessibility**, find **Tungsten Edge**, and **turn on its switch**.

## Status menu

Tungsten Edge lives in the macOS menu bar. Its menu currently includes:

- **Launch at login** — available on macOS 13 and later. If macOS asks for approval, open Login Items in System Settings and approve Tungsten Edge there.
- **Hide/Show System Dock** — equivalent to macOS's own `⌥⌘D`: it toggles the native Dock's auto-hide only and never touches the wake delay you configured. The menu shows `⌥⌘D` as its shortcut hint (macOS owns that shortcut, so it always works). The compact slider immediately below controls the native Dock's wake delay: `常驻` (always visible), `0.1s`–`3.0s`, or `不唤醒` (never wake) — drag it to `不唤醒` and the Dock stays fully out of the way, no longer popping up when the pointer reaches the screen edge. The slider applies on release, since every write restarts Dock.
- **Open System Dock Settings…** — opens Desktop & Dock on Ventura and later, or Dock & Menu Bar on macOS 12. It only opens System Settings; it never writes Dock preferences or restarts Dock.
- **Hide/Show Tungsten Edge 钨极** — switches between always visible and your last auto-hide wake delay. The compact slider immediately below it controls the wake delay: `常驻`, `0.1s`–`3.0s`, or `不唤醒`. When the status menu is closed, the global `⌥⇧⌘D` shortcut performs the same switch; if registration fails, the menu hides its key hint but the command remains clickable. Adding Shift mirrors the system Dock's `⌥⌘D` while releasing the old `⌥⌘E` shortcut back to Safari and Finder.
- **显示中转站** — a checkbox that shows or hides the shelf chip. Unchecking it only hides the chip; stashed file references are kept and come back when you check it again. Note that with the shelf hidden *and* no pinned folders, the whole folder zone disappears, so the strip has no external-file drop target and no 「添加文件夹…」 entry — check it back on to get them.
- **任务条大小 ▸** — four tiers (小 / 中 / 大 / 特大) that scale the taskbar and its capsule together: icons, labels, spacing, corner radius and bar height all follow. 中 is the default and is pixel-identical to previous versions. Switching applies instantly with no transition animation; an open drawer closes so it can be re-measured at the new size. The drawer's own contents and the folder / shelf popups keep their current size.
- **检查更新…** — manually checks for the latest stable version. When an update is available, Tungsten Edge opens the official website for you to download and install it.

Changing native Dock visibility from this menu requires a non-sandboxed build because sandboxed apps cannot write Dock preferences or restart Dock. Opening the settings pane works in either environment.

## Recommended setup (align the minimize animation to the bottom)

If your native Dock lives on the **side or top** of the screen, minimizing a window flies the animation toward the native Dock — out of sync with this bottom taskbar. Move the native Dock back to the **bottom** and set it to auto-hide; the minimize animation will then shrink toward the bottom, matching Tungsten Edge:

- **System Settings → Desktop & Dock → Position on screen → Bottom**, and turn on **Automatically hide and show the Dock**.

To keep the native Dock from ever reappearing, drag the system Dock slider in the status menu to `不唤醒` (never wake): hovering at the screen edge will no longer wake it.

## Roadmap

This is an early public build (v0.3). Known limitations and what's next:

- **Not yet signed/notarized** → first launch needs right-click → Open (above). A signed build is planned.
- **Chinese-only UI** → localization is on the roadmap. A Chinese version of this README is available at [README.zh-CN.md](README.zh-CN.md).
- Feedback and issues are very welcome.

## Community

**WeChat Group**

<img src="assets/wechat-group.png" alt="Tungsten Edge WeChat group QR code" width="280" />

The QR code is updated weekly. If it has expired, please leave a message in [Issues](https://github.com/moonbai-studio/tungsten-edge/issues) and I'll renew it promptly.

Tungsten Edge recognizes and thanks the [LINUX DO](https://linux.do/) community for providing a place for discussion and feedback.

## License

Copyright (C) 2026 Moonbai Studio.

Tungsten Edge is licensed under the GNU General Public License v3.0 or later (`GPL-3.0-or-later`). See [LICENSE](LICENSE).

The application source code, build scripts, and assets required to build it are published in this repository. Code-signing certificates, notarization credentials, account credentials, and other secrets are not source code and are never included.

The license covers the source code; it does not require official signed/notarized binaries or related services to be provided free of charge.

---

## Developers

Release notes for every version are archived under [`Docs/Archive/Releases/`](Docs/Archive/Releases).

Build & run:

```bash
./Scripts/build_and_run.sh
```
</content>
