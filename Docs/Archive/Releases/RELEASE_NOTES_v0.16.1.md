## New and improved

- Pinned folders have a new Display as option in their menu: Folder shows the folder’s own icon, and Stack shows its first few items stacked.
- Improved the landing animation when an app is dragged from Finder onto the taskbar.
- New installs on macOS 26 and later keep the Apps entry next to Finder.
- Some menu wording has been adjusted.

## Fixed

- The Trash icon on the taskbar did not update after files were deleted or the Trash was emptied in Finder.

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

- 固定文件夹右键菜单新增「显示为」：选「文件夹」显示文件夹自身的图标，选「叠放」显示其中前几项的叠放。
- 优化从访达把应用拖进 Dock 栏时的落位动画。
- 全新安装时，macOS 26 及更新系统默认在访达旁保留「应用程序」入口。
- 部分菜单措辞调整。

## 修复

- 在访达中删除文件或清空废纸篓后，Dock 栏上的废纸篓图标不随之更新。

**已知问题：** 个别机器升级后 Dock 栏背景可能发白。临时恢复办法：在「终端」中执行 `launchctl setenv DOCK_LIQUID_GLASS_SYSTEM_VARIANT off`，然后退出并重新打开钨极（重启电脑后需重新执行）。也请在「设置 → 关于」中拷贝「诊断信息」，通过「设置 → 反馈」或用户群发给我们，以便定位修复。

## 安装

**已经装了 0.9.0 或更新的版本？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask tungsten-edge
```

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
