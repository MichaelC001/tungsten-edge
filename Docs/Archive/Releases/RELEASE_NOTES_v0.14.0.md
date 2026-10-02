Tungsten Edge v0.14.0 adds Dark Mode and four interface languages, brings the popups and the settings window in line with the system, and fixes several issues.

- **Added Dark Mode.** The appearance follows the system by default, so the taskbar turns dark when the system is set to dark; to keep the light look, choose **Light** in **Settings → General → Appearance**.
- **Pinned folder, shelf and Trash popups now match the Dock.** The settings window uses the system's grouped layout, and several interface details were refined. The *Taskbar Size* slider has moved to the menu bar menu.
- **Added Spanish, Portuguese, Italian and Korean interfaces,** for 12 languages in total.
- **With *Keep maximized windows above the taskbar* turned on, windows tiled to a screen edge also stay clear of the taskbar.** Fixed windows hidden by some apps staying on the taskbar, the taskbar hiding when a wallpaper or desktop-widget app takes focus, and other issues.

**Known issue:** on a few Macs the taskbar background may turn milky white after updating. To restore it for now, run `launchctl setenv DOCK_LIQUID_GLASS_SYSTEM_VARIANT off` in Terminal, then quit and reopen Tungsten Edge (run it again after restarting the Mac). Please also copy the diagnostic info from **Settings → About** and send it to us through **Settings → Feedback** or the community group, so we can fix it.

## Installing

**Already on 0.13.3?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.14.0 新增深色模式与四种界面语言，文件夹类弹窗与设置窗口改为系统原生样式，并修复多处问题。

- **新增深色模式：** 外观默认跟随系统，系统为深色时 Dock 栏随之变为深色；如需保持浅色，可在「设置 → 通用 → 外观」中选择「浅色」。
- **固定文件夹、中转站与废纸篓的弹窗改为与系统 Dock 一致的样式，** 设置窗口改为系统分组样式，并调整了部分界面细节；「Dock 栏大小」滑块移至状态栏菜单。
- **界面新增西班牙语、葡萄牙语、意大利语与韩语，** 现支持 12 种语言。
- **开启「最大化窗口避开 Dock 栏」时，拖到屏幕边缘平铺的窗口同样会避开 Dock 栏；** 修复部分应用隐藏窗口后仍留在 Dock 栏、壁纸或桌面小组件类应用获得焦点时 Dock 栏被隐藏等问题。

**已知问题：** 个别机器升级后 Dock 栏背景可能发白。临时恢复办法：在「终端」中执行 `launchctl setenv DOCK_LIQUID_GLASS_SYSTEM_VARIANT off`，然后退出并重新打开钨极（重启电脑后需重新执行）。也请在「设置 → 关于」中拷贝「诊断信息」，通过「设置 → 反馈」或用户群发给我们，以便定位修复。

## 安装

**已经在用 0.13.3？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
