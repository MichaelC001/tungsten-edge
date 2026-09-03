Tungsten Edge v0.11.1 is all drag polish and fixes: the slot closes the moment a window card leaves the taskbar, the capsule and the drawer always follow the bar, and a cross-display drop lands on the display you released it on.

- **Improved: Dragging a window card off the taskbar now closes its slot right away and the bar shrinks symmetrically.** Dragging it back reopens a slot under the pointer.
- **Fixed: During a drag the capsule and the drawer no longer drift out of line with the taskbar.** The card being dragged no longer flickers between bright and dim.
- **Fixed: With one taskbar per display, a window card dragged to another display now lands on the bar of the display you released it on.** Not the wrong bar, and no snapping back to the display it came from.
- **Fixed: Dragging a Finder window card with several tabs across displays no longer leaves a duplicate card on the target taskbar.** Releasing with nowhere to land still plays a settling animation instead of freezing in mid-air.

## Installing

**Already on 0.11.0?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. Your Accessibility permission carries over.

**New install:** grab the `.dmg` from the [official website](https://tungstenedge.app) and drag it into Applications, or:

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, **remove** the old entry in **System Settings → Privacy & Security → Accessibility** with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.11.1 全是拖拽上的打磨与修复：把窗口卡拖出 Dock 栏时空位会当场合拢，胶囊和抽屉始终跟着条走，跨屏拖放也总是落在松手的那块屏上。

- **优化：把窗口卡拖出 Dock 栏时，它空出来的位置会当场合拢、条跟着对称收窄。** 拖回条上又会在鼠标底下重新让开一格。
- **修复：拖动过程中胶囊和抽屉不再跟 Dock 栏错位。** 被拖起来的卡片也不再一明一暗地闪。
- **修复：每块屏各一条时把窗口卡拖到另一块屏，现在松手在哪块屏就落到哪块屏的条上。** 不再落错条，也不会闪回原来那块屏。
- **修复：跨屏拖一张带多个标签页的访达窗口卡，目标 Dock 栏上不再多出一张重复的卡。** 松手时没有落点也总有收尾动画，不会僵在半空。

## 安装

**已经在用 0.11.0？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。辅助功能授权不用重新给。

**新装：** 到[官网](https://tungstenedge.app)下 `.dmg` 拖进「应用程序」，或者：

```bash
brew install --cask moonbai-studio/tungsten-edge/tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，在「系统设置 → 隐私与安全性 → 辅助功能」里用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
