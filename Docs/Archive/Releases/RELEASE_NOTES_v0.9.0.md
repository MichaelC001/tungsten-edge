Tungsten Edge v0.9.0 does three things: it is now **signed and notarized by Apple**, it **updates itself**, and on first run it **offers to tuck the system Dock away for you**.

---

## ⚠️ Read this first if you are upgrading

v0.9.0 switches to a proper Apple Developer ID signature. As far as macOS is concerned a changed signature means a different app, so **the Accessibility permission you previously granted no longer applies** — you will see an empty taskbar, or none at all.

**How to fix it** (once only; future updates will not need this):

1. **Quit Tungsten Edge** (status menu → Quit).
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Find the old **Tungsten Edge** entry, **select it and remove it with the「−」button**. Toggling the switch off and on is not enough — the entry has to go.
4. Reopen Tungsten Edge and grant it again when prompted.

The upside: from this version on, a plain double-click opens it. No more right-click-to-open.

---

## Automatic updates

Until now a new version meant going to the website, downloading a disk image and dragging it across by hand. Tungsten Edge now checks on its own, shows you an update window when there is one, and a single click downloads, installs and relaunches it — the browser never enters the picture.

- Automatic checking is on by default. If you would rather it did not reach the network on a schedule, uncheck **Check for updates automatically** in **Settings → About**; it will then only look when you click *Check for Updates…* yourself.
- Homebrew users are unaffected: the cask is now marked as self-updating, so `brew upgrade` will no longer reinstall an older build over the top of a newer one.

## First run: hiding the system Dock

Tungsten Edge and the system Dock both live along the bottom edge of the screen, so showing both means they cover each other up. On first run Tungsten Edge now asks, and **Hide the Dock** sets it up for you — hidden, and staying hidden even when the pointer reaches the bottom edge.

- The Dock restarts, so the screen flashes once. That is normal.
- **Want it back? Press ⌥⌘D at any time** — that is macOS's own shortcut for showing and hiding the Dock. You can also change it later from the Dock slider in the Tungsten Edge status menu.
- If you had already set the Dock to hide itself, the prompt does not appear at all.
- **Not Now** means it will not ask again; the status menu is always there if you change your mind.

## Also

- **Settings → About** now carries a GitHub link. Tungsten Edge is free and open source — if it is useful to you, a Star is the easiest way to help.

---

## Installing

**Download the installer**: grab the `.dmg` from the [official website](https://tungstenedge.app), drag it into Applications, and double-click.

**Homebrew**:

```bash
brew tap moonbai-studio/tungsten-edge
brew trust moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**Accessibility permission**: Tungsten Edge needs it to read and manage your windows, and it guides you through granting it on first run. If you are upgrading, remove the stale entry first as described above.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.9.0 做了三件事：**通过了 Apple 签名与公证**、**加上了自动更新**、**首次运行会主动帮你把系统 Dock 收起来**。

---

## ⚠️ 升级上来的用户请先看这一条

v0.9.0 换成了正式的 Apple 开发者签名。对 macOS 来说，签名变了就等于换了一个应用，**你之前给钨极开的「辅助功能」授权不再生效**——表现是升级后任务条空着、或者干脆不出来。

**怎么恢复**（只需要做这一次，以后升级不会再有）：

1. **退出钨极**（状态栏菜单 → 退出）。
2. 打开「系统设置 → 隐私与安全性 → 辅助功能」。
3. 在列表里找到旧的 **Tungsten Edge**，**选中它，点下面的「−」把它删掉**。直接关开关不管用，必须删掉这一条。
4. 重新打开钨极，按引导重新授权。

好消息是，从这一版开始双击就能打开，不用再右键放行了。

---

## 自动更新

以前发新版，你得自己去官网下 dmg、拖进「应用程序」。现在钨极会自己检查，有新版时弹一个窗口，点一下就下载、安装、重启，全程不用碰浏览器。

- 自动检查默认开着。不想让它定期联网的话，在「设置 → 关于」里把「自动检查更新」取消勾选即可——关掉之后只有你主动点「检查更新…」时才会去查。
- 用 Homebrew 装的用户不受影响：cask 已经标记成「应用自己会更新」，`brew upgrade` 不会再把你降级装回去。

## 首次运行：帮你收起系统 Dock

钨极和系统 Dock 都住在屏幕底边，同时显示会互相遮挡。所以第一次运行时它会问一句，点「帮我隐藏」就替你设好（自动隐藏，而且鼠标碰到底边也不会把它唤出来）。

- 系统 Dock 会闪一下重启，这是正常的。
- **想让它回来，随时按 ⌥⌘D**——那是 macOS 自带的 Dock 显隐快捷键。也可以之后从钨极状态栏菜单里的系统 Dock 滑杆改。
- 如果你早就把系统 Dock 设成自动隐藏了，这个提示不会出现，不会打扰你。
- 点了「以后再说」就不再问；想改随时走状态栏菜单。

## 其它

- 「设置 → 关于」里加了一行 GitHub 链接。钨极是免费开源的，如果它帮到了你，去点个 Star 是最省事的支持方式。

---

## 安装

**下载安装包**：从[官网](https://tungstenedge.app)下载 `.dmg`，拖进「应用程序」，双击打开。

**Homebrew**：

```bash
brew tap moonbai-studio/tungsten-edge
brew trust moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**辅助功能权限**：钨极靠这个权限读取和管理你的窗口，第一次运行时会引导你开启。从旧版升级的用户请按上面那条先删掉旧记录。

需要 macOS 12 或更新版本，Apple 芯片与 Intel 通用。
