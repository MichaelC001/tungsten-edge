Tungsten Edge v0.9.5 fixes one long-standing annoyance — **minimizing a window no longer yanks a sibling window to the front** — and roughly halves idle CPU usage.

---

## Minimizing a window hands the front to whatever was beneath it

When you minimize a window from the taskbar, whatever sat directly beneath it now takes over — another app, or a sibling window of the same app. Previously, for apps with several windows open, macOS would promote one of the app's other windows and lift it above everything else, even when it had been buried at the bottom. That no longer happens, and keyboard focus lands on the window that took over, so you can type right away.

Minimizing with a window's own yellow button is unchanged — that is macOS's native behavior.

## About half the idle CPU

Three rounds of background-polling work: quiet apps are skipped during the 5-second reconcile, the running-app list is cached instead of re-enumerated, message badges are read point-by-point instead of walking the whole Dock tree, and window snapshots are reused when nothing has changed. Measured on the same Mac, same day: idle CPU went from about 1.8% to 0.8%. No behavior changed.

---

## Installing

**Already on 0.9.0 – 0.9.4?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. **Your Accessibility permission carries over.**

**Download the installer**: grab the `.dmg` from the [official website](https://tungstenedge.app), drag it into Applications, and double-click.

**Homebrew**:

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, open **System Settings → Privacy & Security → Accessibility**, **remove** the old entry with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.9.5 修好一个老毛病——**收起窗口时，不再有别的窗口被凭空抬到最前**——并把空闲时的 CPU 占用降了约一半。

---

## 收起窗口后，压在它下面的是谁就轮到谁

从任务条收起一个窗口，现在轮到的是原本压在它正下方的那个——不管是别的应用，还是同一个应用的另一个窗口。以前对开着多个窗口的应用，macOS 会自己挑该应用的另一个窗口顶上来、并抬到所有窗口之上，哪怕它本来埋在最底下。这个问题没有了；键盘焦点也会直接落到接手的那个窗口上，可以立刻打字。

用窗口自己的黄色按钮最小化时行为不变——那是 macOS 的原生行为。

## 空闲 CPU 约减半

三轮后台轮询的优化：5 秒对账时跳过没动静的应用、运行中应用的名单改为缓存、消息角标改为定点读取而不是遍历整棵 Dock 树、窗口快照在没有变化时复用。同一台 Mac 同日实测，空闲 CPU 从约 1.8% 降到 0.8%。行为没有任何变化。

---

## 安装

**已经是 0.9.0 – 0.9.4 的话**：什么都不用做，更新会自己找上门；也可以去「设置 → 关于」点「检查更新…」。**辅助功能授权照旧有效。**

**下载安装包**：从[官网](https://tungstenedge.app)下载 `.dmg`，拖进「应用程序」，双击打开。

**Homebrew**：

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**从 0.8.0 或更早升上来？** 那些版本没有经过 Apple 签名，macOS 会把这一版当成另一个应用，旧的辅助功能授权不会生效。先完全退出钨极，打开「**系统设置 → 隐私与安全性 → 辅助功能**」，用「−」按钮**删掉**旧条目（关掉再打开不行），然后重新打开钨极并重新授权。

需要 macOS 12 或更新。通用二进制——Apple 芯片和 Intel 都支持。
