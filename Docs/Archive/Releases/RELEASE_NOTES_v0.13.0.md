Tungsten Edge v0.13.0 brings a new brand mark, puts the size slider back in Settings, and stops other processes from moving the taskbar.

- **The app and menu bar icons now carry the new brand mark, rebuilt on Apple's icon grid so their size and padding match other apps in the Dock.**
- **The Taskbar Size slider is back in Settings, and it changes the same value as dragging at a divider on the taskbar.**
- **Fixed: other processes — window managers, for instance — can no longer move or resize the taskbar through Accessibility, which could leave the bar stranded mid-screen after you made it shorter.**

## Installing

**Already on 0.12.2?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

本版换了新的品牌标志，设置窗口里重新有了大小滑块，并挡住了别的程序挪动 Dock 栏。

- **应用图标和菜单栏图标换成了新的品牌标志，并按苹果的图标网格重做，在程序坞里的大小和留边与其他应用一致。**
- **设置窗口里重新有了「Dock 栏大小」滑块，它和在 Dock 栏分隔处上下拖动改的是同一个值。**
- **修复：别的程序（比如窗口管理工具）不能再通过辅助功能挪动或缩放 Dock 栏——此前可能出现把高度调小之后，Dock 栏跑到屏幕中间。**

## 安装

**已经在用 0.12.2？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
