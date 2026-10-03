## New and improved

- Pinned folders now match the Dock: the icon shows the folder’s first three items stacked, and folders sit at the right end next to the Trash. The shelf has moved to follow the pinned apps on the left.
- New installs start with the Downloads folder pinned.
- A folder dragged in from Finder now opens a gap on the taskbar and is pinned where it is dropped.
- With *Keep maximized windows above the taskbar* turned on, double-clicking a window’s title bar restores the window to its original size.

## Fixed

- The original file was not moved when a file was dragged out of a popup.
- Popups shrank to a small box when their contents changed.
- Desktop widgets appeared on the taskbar.
- Minimized windows occasionally appeared on another display’s taskbar.
- Feedback drafts were lost when the settings window was closed.

**Known issue:** on a few Macs the taskbar background may turn milky white after updating. To restore it for now, run `launchctl setenv DOCK_LIQUID_GLASS_SYSTEM_VARIANT off` in Terminal, then quit and reopen Tungsten Edge (run it again after restarting the Mac). Please also copy the diagnostic info from **Settings → About** and send it to us through **Settings → Feedback** or the community group, so we can fix it.

## Installing

**Already on 0.14.0?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

## 新增与改进

- 固定文件夹改为与系统 Dock 一致：图标显示为文件夹内前三项的叠放，并移至右端废纸篓旁；中转站移至左侧固定应用之后。
- 新安装默认固定「下载」文件夹。
- 从访达拖入文件夹时，Dock 栏会让出空位，松开即固定在该位置。
- 开启「最大化窗口避开 Dock 栏」时，双击窗口标题栏可恢复窗口原来的大小。

## 修复

- 从弹窗中拖出文件后，原文件未被移动。
- 弹窗内容变化时缩成小块。
- 桌面小组件出现在 Dock 栏上。
- 最小化的窗口偶尔出现在另一块屏幕的 Dock 栏上。
- 关闭设置窗口后，反馈草稿丢失。

**已知问题：** 个别机器升级后 Dock 栏背景可能发白。临时恢复办法：在「终端」中执行 `launchctl setenv DOCK_LIQUID_GLASS_SYSTEM_VARIANT off`，然后退出并重新打开钨极（重启电脑后需重新执行）。也请在「设置 → 关于」中拷贝「诊断信息」，通过「设置 → 反馈」或用户群发给我们，以便定位修复。

## 安装

**已经在用 0.14.0？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
