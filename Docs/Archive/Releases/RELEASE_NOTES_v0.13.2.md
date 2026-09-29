Tungsten Edge v0.13.2 adjusts pinned folders and the app icon, and shrinks the download.

- **Pinned folders are now the same size as app icons, with no name below the icon; the full name appears on hover.**
- **Updated the app icon for the new icon specifications of macOS 26 and macOS 27, so it is no longer shrunk into a gray frame, and added support for the dark and tinted icon styles.**
- **Fixed clicking the Finder icon with no Finder window open always opening the home folder instead of the location set in Finder Settings.**
- **The empty drawer hint now reads “Drag apps here from the taskbar”.**
- **Significantly reduced the download size, from about 9.1 MB to about 4.5 MB, with no change in functionality.**

## Installing

**Already on 0.13.1?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

本版调整了固定文件夹与应用图标，并缩小了安装包。

- **固定文件夹改为与应用图标同样大小，图标下方不再显示名称，悬停时显示完整名称。**
- **应用图标适配 macOS 26 与 macOS 27 的新图标规范，不再被缩小并套上灰色底框，支持深色与着色图标风格。**
- **修复没有访达窗口时，点击访达图标总是打开个人文件夹、不按访达设置的位置打开的问题。**
- **空抽屉的提示改为「从钨极 Dock 栏把应用拖到这里」。**
- **大幅缩减安装包体积，由约 9.1 MB 减小至约 4.5 MB，功能不变。**

## 安装

**已经在用 0.13.1？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
