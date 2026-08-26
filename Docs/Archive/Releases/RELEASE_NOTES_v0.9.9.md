Tungsten Edge v0.9.9 takes the first step toward real multi-display support: the taskbar can now be pinned to one display instead of following the mouse. It also clears out the last cases where a rapid click did nothing, and stops the Settings window from shuffling its text sideways.

*(0.9.8 was skipped — its tag went out before a Chinese wording fix landed, and tags here cannot be moved.)*

---

## Pin the taskbar to one display

**The status menu has a new row: "Show taskbar on".** Hover it and you get *Follow the mouse* plus one entry per connected display; the current one is ticked, and picking another moves the taskbar there immediately.

- **Following the mouse is still the default**, so if you never open that menu nothing about this release changes for you.
- **While pinned, the taskbar stays put** — moving the pointer to another display no longer drags it along, and the bottom-edge wake only arms on the display you pinned it to.
- **Unplug the pinned display and the taskbar falls back to the main display**, then returns on its own when that display comes back. Your choice is remembered through the whole round trip; a display that is currently absent stays selected and shows as *(disconnected)*.
- The row is hidden when you only have one display and have not pinned anything — but it stays visible while pinned even on a single display, otherwise unplugging your external monitor would leave no way back to *Follow the mouse*.

This is mode 2 of a four-mode multi-display plan; "show on every display" and "each display shows only its own windows" are still to come.

## Clicking

**Rapidly clicking a card to minimize and restore no longer leaves a click doing nothing.** Four separate causes, all diagnosed from click traces on an installed Release build:

- A window you just restored is no longer written off as inactive because a sibling window's focus reading lagged behind.
- When the system is about to promote a different window of the same app, the taskbar now predicts that handover, so clicking that window right after minimizing its sibling minimizes it instead of doing nothing.
- Strict back-and-forth on one window is no longer mistaken for window ping-pong and downgraded to a harmless no-op.
- A minimize that arrives while the restore genie is still playing is retried until the animation ends, instead of being dropped. Over a 282-click session: zero clicks lost.

## Settings

**Switching to the Taskbar or Feedback tab no longer shifts the text sideways.** Those two tabs are the tallest of the six, so the window had to grow — and during that 0.2 s animation an overlay-free scrollbar appeared, took a slice of the width, and pushed the fixed-width content over until the animation ended.

---

## Installing

**Already on 0.9.0 – 0.9.7?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. **Your Accessibility permission carries over.**

**Download the installer**: grab the `.dmg` from the [official website](https://tungstenedge.app), drag it into Applications, and double-click.

**Homebrew**:

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, open **System Settings → Privacy & Security → Accessibility**, **remove** the old entry with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.9.9 迈出了多屏支持的第一步：Dock 栏可以固定在某一块屏幕上，不再总是跟着鼠标跑。另外把最后几处「连着点、点了没反应」清干净了，设置窗口切页时文字乱挪的毛病也修了。

*（跳过了 0.9.8——它的标签推出去之后才发现一处中文文案要改，而标签推出去就挪不动了。）*

---

## Dock 栏可以固定到某一块屏幕

**状态栏菜单里多了一行「钨极 Dock 栏显示在」**，鼠标移上去展开：「跟随鼠标」，加上每块接着的屏各一项。当前那项打勾，点另一项，Dock 栏立刻挪过去。

- **默认仍然是「跟随鼠标」**，所以你要是不去开那个菜单，这一版对你来说什么都没变。
- **固定之后 Dock 栏就待着不动**——鼠标挪到别的屏不会再把它带过去，底边唤醒也只在你固定的那块屏上生效。
- **固定的那块屏拔掉，Dock 栏会暂时回到主屏**，屏幕接回来它自己就归位。这一来一回你的选择一直留着；当前不在场的屏仍然是选中状态，显示成「（未连接）」。
- 只接一块屏、又没固定过时，这一行整个不显示；但**固定态下即使只剩一块屏也照显**——不然你固定到外接屏再把它拔了，就没有入口切回「跟随鼠标」了。

这是四档多屏方案里的第二档，「所有屏都显示」和「各屏只显示本屏窗口」还在后面。

## 点击

**连着点收起、还原，不会再出现「点了没反应」。** 四个各自独立的原因，都是从装机 Release 版的点击轨迹里查出来的：

- 刚被你还原的窗口，不会再因为兄弟窗口的焦点读数慢了半拍，就被判成「没在前台」。
- 系统正要把同一个应用的另一扇窗口顶上来时，Dock 栏现在能预判这次交接——所以你刚收起一扇、马上点另一扇，点的是收起，而不是什么都没发生。
- 老老实实在同一扇窗口上来回点，不会再被误认成「两扇窗口乒乓」而降级成一次无效操作。
- 还原动画还在放的时候落下的收起指令，现在会一直重试到动画结束，而不是被直接丢掉。282 次点击的实测里：一次都没丢。

## 设置

**切到「Dock 栏」和「反馈」页时，文字不再横向挪一下。** 这两页是六页里最高的，切过去窗口要长高——而那 0.2 秒的动画里会冒出一条占位式滚动条，吃掉一截宽度，把写死宽度的内容整体挤偏，动画结束才弹回去。

---

## 安装

**已经在用 0.9.0 – 0.9.7？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。**辅助功能授权不用重新给。**

**下载安装包**：到[官网](https://tungstenedge.app)下 `.dmg`，拖进「应用程序」，双击打开。

**Homebrew**：

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，打开「系统设置 → 隐私与安全性 → 辅助功能」，用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
