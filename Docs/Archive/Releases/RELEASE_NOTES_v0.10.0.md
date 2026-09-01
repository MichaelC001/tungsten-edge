Tungsten Edge v0.10.0 moves four everyday switches out of the settings window and into the status-bar menu, and smooths out full screen, Split View and dark wallpapers.

- **The Taskbar pane is gone from Settings — its four switches now live in the status-bar menu.** *Show Shelf*, *Show app name on hover*, *Keep maximized windows above the taskbar* and *Taskbar Size* are one click away from the menu bar icon, next to where the taskbar is shown. Your existing choices are kept; only their location changed. Settings is five pages now instead of six.
- **The taskbar comes back faster after you leave full screen.** It used to take 2–3 seconds and now takes under half a second, and both transitions fade instead of snapping. **The taskbar also stays out of the way in Split View.**
- **Card titles are easier to read on dark wallpapers.**
- **New *Show Setup Guide Again* entry in the status-bar menu**, so long-time users can still get the three recommended Dock settings from the first-launch guide.

## Installing

**Already on 0.9.x?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.10.0 把四个常用开关从设置窗口挪进了状态栏菜单，并修掉全屏、分屏、深色壁纸下的几处不顺手。

- **设置里的「Dock 栏」整页搬进了状态栏菜单。**「显示中转站」「鼠标悬停显示应用名」「最大化窗口避开 Dock 栏」「Dock 栏大小」这四项，现在点菜单栏图标就能改，和「钨极 Dock 栏显示在」在同一块。你原来的设置值都保留，只是位置换了；设置窗口从六页变成五页。
- **退出全屏后 Dock 栏回来得更快。** 原来要等 2~3 秒，现在半秒内；进出全屏也改成了淡入淡出。**分屏时 Dock 栏不再挡住内容。**
- **深色壁纸下，窗口卡上的标题看得更清楚了。**
- **状态栏菜单新增「重新打开新手引导」**，装了很久的用户也能拿到「隐藏系统 Dock」那三条推荐设置。

## 安装

**已经在用 0.9.x？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
