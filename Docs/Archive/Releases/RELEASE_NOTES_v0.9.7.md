Tungsten Edge v0.9.7 is a fix release: clicking is steadier around minimize and window switching, the taskbar finally scrolls on trackpads and Magic Mice, and the License tab stops pointing you at an email that was never sent.

---

## One thing that changes (read this first)

**The License tab no longer has a place to paste a key.** The field, the Activate button and the "Not activated" line are gone for now. No license key has ever been issued — issuing starts with 1.0 — so an empty box could only make you wait for mail that was never coming, and one of you wrote in to say exactly that. The tab now states what is actually true: **licensing opens with 1.0, Tungsten Edge is free until then, and founding users get a permanent free key when it does.** The paste field comes back in the release that starts issuing keys.

## Clicking

- **Alternating quickly between two windows of one app no longer minimizes the window you clicked.** Focus handover takes a moment, and a click that landed mid-handover could still read the window as frontmost — which means "collapse it". While a sibling window is still taking focus, such a click is now treated as a redundant activate instead. An extra activate is harmless; a wrong minimize is not.
- **Clicking a card again before the minimize animation has finished no longer raises a different window of the same app.** The second click now waits for the minimize to actually land, then restores the window you asked for, and waits for it to be back on screen before moving focus — the 40–100 ms in which it was still off screen is exactly when a sibling window used to get promoted instead.

## Scrolling

**Trackpads, Magic Mice and mice with smooth-scrolling drivers can now scroll the taskbar.** The taskbar only ever handled notched wheels, so on every other pointing device the chips that overflowed the screen were simply out of reach (issue #14). A vertical swipe now steps the bar sideways; a horizontal swipe passes straight through, keeping the system's own momentum and rubber-banding. Direction follows the natural-scrolling switch of the device you are actually using — macOS keeps separate ones for mouse and trackpad.

Also: after you subscribe, the confirmation message now tells you to check your spam folder if the mail is not in your inbox.

---

## Installing

**Already on 0.9.0 – 0.9.6?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. **Your Accessibility permission carries over.**

**Download the installer**: grab the `.dmg` from the [official website](https://tungstenedge.app), drag it into Applications, and double-click.

**Homebrew**:

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, open **System Settings → Privacy & Security → Accessibility**, **remove** the old entry with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.9.7 是一次修复版：点击在最小化和窗口切换前后更稳了，触控板和妙控鼠标终于能滚动 Dock 栏，「授权」页也不再让你去等一封根本没发出的邮件。

---

## 先说一处变化（升级后会不一样）

**「授权」页里那个粘贴授权码的输入框暂时收起来了**，激活按钮和「未激活」那行状态也一起没了。授权码一条都还没发放过——要到 1.0 才开始发——所以那个空框只会让人白等一封永远不会来的邮件，已经有用户为这件事找过来。现在这一页直说实话：**授权从 1.0 开始，在那之前钨极完全免费，原始用户到时会拿到一条永久免费的授权码。** 等到真的开始发放的那一版，输入框会回来。

## 点击

- **两个窗口来回快点，不会再把你点的那扇误收起来了。** 焦点交接要花一点时间，交接还没走完时落下的点击，可能仍然读到「这扇在前台」——而「在前台」的含义就是「再点一下收起来」。现在只要兄弟窗口还在接管焦点，这种点击一律降级成「多余地激活一次」。多激活一次没有代价，错误地收起来有。
- **最小化动画没走完就再点一下，不会再把同一个应用的另一扇窗口顶上来。** 第二次点击现在会等最小化真正落地，再还原你要的那扇，并且等它真的回到屏幕上才去移动焦点——它还在屏幕外的那 40–100 毫秒，正是以前兄弟窗口被顶上来的那个空档。

## 滚动

**触控板、妙控鼠标，以及带平滑滚动驱动的鼠标，现在都能滚动 Dock 栏了。** 此前 Dock 栏只认带档位的滚轮，所以在其他所有指点设备上，图标多到放不下时那些被挤出屏幕的根本够不着（issue #14）。现在竖着滑就是让 Dock 栏横向走一步；横着滑原样放行，系统自己的惯性和回弹都保留。方向跟随你手上这个设备的「自然滚动」开关——macOS 给鼠标和触控板各留了一个。

另外：订阅成功后的提示补了一句，收件箱里没有的话记得看一下垃圾邮件。

---

## 安装

**已经在用 0.9.0 – 0.9.6？** 什么都不用做——更新会自己找上门，也可以在「设置 → 关于」里点「检查更新…」。**辅助功能授权不用重新给。**

**下载安装包**：到[官网](https://tungstenedge.app)下 `.dmg`，拖进「应用程序」，双击打开。

**Homebrew**：

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**从 0.8.0 或更早的版本上来？** 那些版本没有苹果签名，在 macOS 眼里这是另一个应用，旧的辅助功能授权对它无效。请先完全退出钨极，打开「系统设置 → 隐私与安全性 → 辅助功能」，用「−」**删掉**旧条目（只关掉再打开不够），再重新打开钨极并重新授权。

需要 macOS 12 或更新版本。通用架构——Apple 芯片与 Intel 都可以。
