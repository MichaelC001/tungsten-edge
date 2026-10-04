## New and improved

- Scrolling on the drawer icon pages through the drawer’s apps three at a time; the apps shown on the icon open with a click, and the bottom-right cell opens the whole drawer.
- The drawer panel has been redesigned to match the pinned folder popup: app names appear under the icons, and the panel scrolls when there are many apps.
- The drawer no longer puts running apps first: apps can be dragged to any position and stay in place when they launch or quit.

## Fixed

- Icons in popups shifted to the left when *Show scroll bars* was set to *Always*.

**Known issue:** on a few Macs the taskbar background may turn milky white after updating. To restore it for now, run `launchctl setenv DOCK_LIQUID_GLASS_SYSTEM_VARIANT off` in Terminal, then quit and reopen Tungsten Edge (run it again after restarting the Mac). Please also copy the diagnostic info from **Settings → About** and send it to us through **Settings → Feedback** or the community group, so we can fix it.

## Installing

**Already on 0.9.0 or later?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask tungsten-edge
```

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

## 新增与改进

- 在抽屉图标上滚动，可按三个一组翻看抽屉中的应用；图标上显示的应用可直接点开，点右下格展开整个抽屉。
- 抽屉面板界面更新：与固定文件夹弹窗风格一致，图标下方显示应用名称，应用较多时可上下滚动。
- 抽屉不再把运行中的应用排在前面：应用可拖到任意位置，启动或退出时位置保持不变。

## 修复

- 系统设为「始终显示滚动条」时，弹窗中的图标整体偏左。

**已知问题：** 个别机器升级后 Dock 栏背景可能发白。临时恢复办法：在「终端」中执行 `launchctl setenv DOCK_LIQUID_GLASS_SYSTEM_VARIANT off`，然后退出并重新打开钨极（重启电脑后需重新执行）。也请在「设置 → 关于」中拷贝「诊断信息」，通过「设置 → 反馈」或用户群发给我们，以便定位修复。

## 安装

**已经装了 0.9.0 或更新的版本？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask tungsten-edge
```

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
