Tungsten Edge v0.13.3 fixes a drag-and-drop issue.

- **Fixed apps and files dragged out of a pinned folder or shelf popup not dropping onto the taskbar.**

## Installing

**Already on 0.13.2?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

本版修复了一处拖放问题。

- **修复从固定文件夹或中转站弹窗中拖出的应用和文件无法放入 Dock 栏的问题。**

## 安装

**已经在用 0.13.2？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
