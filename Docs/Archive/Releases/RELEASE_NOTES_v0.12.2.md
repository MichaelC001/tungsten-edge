Tungsten Edge v0.12.2 fixes three display and settings issues and refines some interface details.

- **Fixed the taskbar backing rendering milky white on some Macs after upgrading; if the glass material cannot be identified, it now falls back to transparent glass.**
- **Fixed the Check for updates automatically checkbox not following your click in Settings.**
- **Fixed a white ring around some apps' small icons.**
- **Refined some interface details.**

## Installing

**Already on 0.12.1?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

本版修复三处显示与设置问题，并调整了部分界面细节。

- **修复部分设备升级后 Dock 栏底板显示为乳白色的问题；无法识别玻璃材质时将回退为透明玻璃。**
- **修复设置中「自动检查更新」的勾选状态不随点击更新的问题。**
- **修复部分应用的小尺寸图标出现白色外圈的问题。**
- **部分界面细节调整。**

## 安装

**已经在用 0.12.1？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
