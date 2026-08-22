Tungsten Edge v0.9.3 fixes one important thing: **clicking a window's card focuses that window again.** A recent macOS change had quietly broken window-level focus for taskbar-style apps — with two visible symptoms: keyboard input not following the click, and, worse, a click sometimes **minimizing** the window instead of bringing it forward.

---

## Clicking a card truly focuses that window again

On recent macOS 26 (Tahoe) systems, Apple silently disabled the private mechanism that taskbar and window-switcher apps use to hand a specific window keyboard focus. The system calls still report success — they just stopped doing anything. For Tungsten Edge that meant:

- After clicking a card, the window rose to the front **visually**, but typing still went to the previously focused window — you had to click inside the window once more.
- Clicking the card of a background window could **minimize it instead of focusing it** when another window of the same app was frontmost (reproducible with any multi-window app).

Switching between apps kept working the whole time, which is why the breakage was easy to miss. v0.9.3 moves focus delivery to an event path that current macOS still honors — clicking a card now lands both the window and your keyboard where you clicked, and the wrong-minimize is gone. There is also a new safety net: should macOS ever break the focus channel again, the failure will degrade to "needs a second click" rather than "minimizes the wrong window".

## Open at Login now works on macOS 12

On Monterey the **Open at Login** toggle used to be grayed out (it relied on an API that requires macOS 13). It now uses the classic login-items list on macOS 12: the entry appears under **System Preferences → Users & Groups → Login Items**, where you can also see and remove it yourself. macOS 13 and newer keep using the modern mechanism, unchanged.

One honest caveat: this path has not yet been verified on a physical Monterey machine. If Open at Login misbehaves for you on macOS 12, please [open an issue](https://github.com/moonbai-studio/tungsten-edge/issues).

Nothing else in the app changed in this release.

---

## Installing

**Already on 0.9.0, 0.9.1 or 0.9.2?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. **Your Accessibility permission carries over.**

**Download the installer**: grab the `.dmg` from the [official website](https://tungstenedge.app), drag it into Applications, and double-click.

**Homebrew**:

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, open **System Settings → Privacy & Security → Accessibility**, **remove** the old entry with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.9.3 只修一件要紧事：**点窗口卡，焦点真正跟过去。** macOS 前段时间的一次更新悄悄弄坏了任务条类应用的窗口级聚焦——症状有两个：点了卡片之后打字打不进那个窗口；更糟的是，点击有时会把窗口**最小化**而不是带到前台。

---

## 点窗口卡，焦点真正跟过去了

在较新的 macOS 26 (Tahoe) 上，苹果悄悄废掉了任务条、窗口切换器这类应用用来「把键盘焦点交给指定窗口」的那条系统私有通道——调用照样返回成功，实际什么都不做。对钨极来说，这意味着：

- 点了卡片，窗口**看起来**到了最前，但打字还是进的原来那个窗口，得再点一下窗口内部才行。
- 同一个应用有别的窗口在前台时，点后台窗口的卡片可能把它**最小化**而不是聚焦（任何多窗口应用都能复现）。

跨应用点击一直是正常的，所以这个坏点很容易被忽略。v0.9.3 把聚焦换到了一条当前 macOS 仍然认的事件通道上——现在点卡片，窗口和键盘焦点会一起落到你点的地方，误最小化也随之消失。另外加了一层保险：将来 macOS 若再把聚焦通道弄坏，症状只会退化成「要多点一下」，不会再回到「误最小化」。

## 「登录时启动」在 macOS 12 上可用了

Monterey 上「登录时启动」原来是灰的（它依赖一个要求 macOS 13 的接口）。现在 macOS 12 走经典的登录项列表：条目会出现在「**系统偏好设置 → 用户与群组 → 登录项**」里，你自己也能看到、能删除。macOS 13 及更新的系统照旧走新机制，没有变化。

一句实话：这条路径还没在 Monterey 实机上验证过。如果你在 macOS 12 上发现「登录时启动」不正常，请[提个 issue](https://github.com/moonbai-studio/tungsten-edge/issues)。

这一版没有改动其它功能。

---

## 安装

**已经是 0.9.0、0.9.1 或 0.9.2 的话**：什么都不用做，更新会自己找上门；也可以去「设置 → 关于」点「检查更新…」。**辅助功能授权照旧有效。**

**下载安装包**：从[官网](https://tungstenedge.app)下载 `.dmg`，拖进「应用程序」，双击打开。

**Homebrew**：

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**从 0.8.0 或更早升上来？** 那些版本没有经过 Apple 签名，macOS 会把这一版当成另一个应用，旧的辅助功能授权不会生效。先完全退出钨极，打开「**系统设置 → 隐私与安全性 → 辅助功能**」，用「−」按钮**删掉**旧条目（关掉再打开不行），然后重新打开钨极并重新授权。

需要 macOS 12 或更新。通用二进制——Apple 芯片和 Intel 都支持。
