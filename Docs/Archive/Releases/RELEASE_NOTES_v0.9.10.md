Tungsten Edge v0.9.10 fixes two problems users reported. No new features, and nothing else changes.

- **The taskbar no longer ends up on a single desktop.** After a fullscreen space closed it could vanish from every other desktop and never come back on its own. ([#19](https://github.com/moonbai-studio/tungsten-edge/issues/19))
- **An app you have not launched yet shows its localized name in the hover bubble.** It used to show the English original until the app was running, then switch back on quit.

## Installing

**Already on 0.9.x?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.9.10 修掉两条用户报的问题。没有新功能，也没有其他行为变化。

- **多桌面下 Dock 栏只在一个桌面上出现的问题修好了。** 退出全屏后，Dock 栏可能只剩一个桌面看得到，而且不会自己恢复。（[#19](https://github.com/moonbai-studio/tungsten-edge/issues/19)）
- **未启动的应用，名字不会再是英文。** 中文系统下，抽屉里没启动的「系统设置」显示成 System Settings；现在未启动、已启动、退出后都是同一个中文名。

## 安装

**已经在用 0.9.x？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
