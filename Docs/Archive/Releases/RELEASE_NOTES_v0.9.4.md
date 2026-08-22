Tungsten Edge v0.9.4 polishes one thing: **a restored window now comes back already focused** — its traffic lights are colored the moment it appears, matching the native Dock.

---

## Restored windows come back already focused

Restoring a minimized window used to show the window first, with focus catching up afterwards (gray traffic lights turning colored). Tungsten Edge now brings the app forward right before the restore, so the window animates in already focused. When the app still has another window visible on screen, restore behaves as before.

Nothing else in the app changed in this release.

---

## Installing

**Already on 0.9.0 – 0.9.3?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. **Your Accessibility permission carries over.**

**Download the installer**: grab the `.dmg` from the [official website](https://tungstenedge.app), drag it into Applications, and double-click.

**Homebrew**:

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, open **System Settings → Privacy & Security → Accessibility**, **remove** the old entry with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.9.4 只打磨一件事：**还原回来的窗口，出现时就已经是聚焦的**——红绿灯一露面就是彩色的，和原生 Dock 一致。

---

## 还原的窗口回来时就已聚焦

以前还原最小化窗口时，窗口先出现、焦点才跟上（红绿灯由灰变彩）。现在钨极会在还原开始前先把应用带到前台，窗口带着焦点进场。应用还有其他窗口显示在屏幕上时，行为保持不变。

这一版没有改动其它功能。

---

## 安装

**已经是 0.9.0 – 0.9.3 的话**：什么都不用做，更新会自己找上门；也可以去「设置 → 关于」点「检查更新…」。**辅助功能授权照旧有效。**

**下载安装包**：从[官网](https://tungstenedge.app)下载 `.dmg`，拖进「应用程序」，双击打开。

**Homebrew**：

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**从 0.8.0 或更早升上来？** 那些版本没有经过 Apple 签名，macOS 会把这一版当成另一个应用，旧的辅助功能授权不会生效。先完全退出钨极，打开「**系统设置 → 隐私与安全性 → 辅助功能**」，用「−」按钮**删掉**旧条目（关掉再打开不行），然后重新打开钨极并重新授权。

需要 macOS 12 或更新。通用二进制——Apple 芯片和 Intel 都支持。
