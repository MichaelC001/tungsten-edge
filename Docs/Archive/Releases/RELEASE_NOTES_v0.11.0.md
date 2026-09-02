Tungsten Edge v0.11.0 finishes multi-display support: a taskbar on every display, optionally listing only the windows that sit on that display, and window cards you can drag from one display's bar onto another.

- **New: The taskbar can now show on every display.** The *Show taskbar on* submenu in the menu bar icon is split into two groups: *on one display* (follow the mouse, or pinned to one), or *one taskbar per display*.
- **New: With one taskbar per display, you can also pick *Show only this display's windows*.** Each taskbar then lists only the windows sitting on that display, and the other display's windows stay out of it.
- **New: Window cards can be dragged across displays.** Drag one from a display's taskbar onto another display's and the window moves across with it — without being forced to the front.
- **Improved: Swiping between desktops no longer turns the taskbar into a solid grey block for the length of the slide.** White in light appearance.

## Installing

**Already on 0.10.x?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.11.0 把多屏支持做完了：Dock 栏可以每块屏各一条，还能让每块屏只显示自己屏上的窗口；窗口卡也能从一块屏的条拖到另一块屏。

- **新增：Dock 栏现在可以每块屏各一条。** 菜单栏图标里的「钨极 Dock 栏显示在」分成了两组：上面一组是「只在一块屏上」（跟随鼠标，或固定到某一块），下面一组是「每块屏各一条」。
- **新增：每块屏各一条时，还能选「只显示本屏的窗口」。** 每条 Dock 栏只列出这块屏上的窗口，别的屏的窗口不再混进来。
- **新增：窗口卡可以跨屏拖。** 从一块屏的 Dock 栏拖到另一块屏的条上，窗口跟着搬过去，也不会被强行拉到最前面。
- **优化：在桌面之间左右滑动时，Dock 栏不再短暂变成一整块灰色。** 浅色外观下是白色。

## 安装

**已经在用 0.10.x？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
