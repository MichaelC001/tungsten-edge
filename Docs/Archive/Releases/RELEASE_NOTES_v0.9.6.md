Tungsten Edge v0.9.6 is the largest feature release so far: the settings window is now six tabs, you can send feedback from inside the app — with screenshots and screen recordings attached — and the interface language, the show/hide shortcut and the mouse-wheel direction are all yours to change.

---

## Three things that move (read this first)

- **Open at Login is the first item in the status menu** — it is no longer in the settings window.
- **The status menu no longer carries *Check for Updates…* or the version line.** Both moved to **Settings → About**. The menu keeps a single update surface: an **Install x.y.z…** row with a red dot, shown only while an update is actually waiting.
- **The chip menu's *Recent Files* became *Frequently Used Files***, ordered by how often you open each file. macOS keeps no open counts, so Tungsten Edge starts counting from this version: right after upgrading the order looks exactly as it did before, and it takes a while of ordinary use before the two diverge.

## The settings window: six tabs

One page had outgrown the screen, so the window takes the classic macOS preferences shape: **General / Taskbar / Advanced / License / Feedback / About**, with the window title following the selected tab. Switching tabs never loses something you half-typed.

## Feedback from inside the app, with screenshots and recordings

**Settings → Feedback**: pick a type (Bug Report / Feature Suggestion / Other) and the box offers a matching hint telling you what is most useful to write. There is an optional contact field.

**Up to 3 attachments** — images up to 10 MB each, videos up to 30 MB each, 40 MB in total. Attachments are stored in a private bucket and deleted automatically after at most 90 days.

When a submission fails, it now says why — offline, sent too often, the attachment channel is full for the day, the server is unavailable — instead of always telling you to check your network. When the attachment channel is full, removing the attachments and sending the text alone still works.

## Pick the interface language

**Settings → General** gains a language picker: Follow System / 简体中文 / English. Follow System is the default, so nothing changes for existing users. The choice applies on the next launch, and a dialog offers to relaunch right away.

## The show/hide shortcut is rebindable

Still ⌥⇧⌘D by default. To change it, go to **Settings → General** and press the combination you want. Combinations macOS owns (⌥⌘D among them) are refused, and if a new combination cannot be registered, it reverts to the previous one.

## Reverse the mouse wheel on its own

**Settings → General**, **off by default**. Turning it on reverses the mouse wheel only — trackpads and the Magic Mouse are untouched. This is the thing people coming from Windows trip over: flipping the system's "natural scrolling" reverses the trackpad along with the wheel.

## An app's windows in the right-click menu

Kept icons, messaging apps, apps in the drawer, the persistent Finder icon — right-clicking any of them now lists all of that app's windows at the top of the menu, the way the Dock does: a checkmark on the frontmost window, a diamond on a group that is fully minimized, and one click switches to it (restoring it if it was minimized). **For minimized windows of drawer and messaging apps, this is the first place you can click them at all.**

A single window's card does not list anything — it *is* the window.

## The License tab

Tungsten Edge becomes a one-time purchase at 1.0 — no subscription. This version ships the verification half: a license key is checked locally, with no network activation and no device binding. **It is still entirely free today**, and everyone who confirms their email on the founding-user list before 1.0 keeps it free forever.

## Fixes

- **Ghostty phantom cards** — closing the last tab of a minimized window left a dead card on the taskbar until the taskbar was restarted.
- **The unread badge no longer depends on the messaging zone.** Previously only apps that made it into the zone got a badge, and Messages, Slack and Discord never could, so they never had one. The badge now follows whether an app is a messaging app at all, independently of the zone. The same change fixes WeChat and Telegram showing a wake-only icon in the zone plus a duplicate card elsewhere.

---

## Installing

**Already on 0.9.0 – 0.9.5?** Do nothing — the update will find you, or use *Check for Updates…* in **Settings → About**. **Your Accessibility permission carries over.**

**Download the installer**: grab the `.dmg` from the [official website](https://tungstenedge.app), drag it into Applications, and double-click.

**Homebrew**:

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, open **System Settings → Privacy & Security → Accessibility**, **remove** the old entry with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.9.6 是迄今最大的一次功能更新：设置窗口整个重排成了六个标签页，应用内可以直接发反馈（能带截图和录屏），界面语言、显隐快捷键、鼠标滚轮方向都可以自己调了。

---

## 先说三处变化（升级后会不一样）

- **「登录时启动」在状态栏菜单第一项**，不在设置窗口里了。
- **状态栏菜单里没有「检查更新…」和版本号了**，它们搬到了「设置 → 关于」。菜单里只在真的有更新等着装的时候，才出现一行带红点的「安装 x.y.z…」。
- **右键菜单里的「最近使用的文件」变成了「最常用的文件」**，按你打开的次数排序。macOS 不记次数，所以钨极从这一版起自己开始记——刚升级时顺序和以前一样，用一阵子才会拉开差距。

## 设置窗口：六个标签页

原来一页装不下了，现在是 macOS 偏好设置那种经典样子：**通用 / 任务条 / 高级 / 授权 / 反馈 / 关于**，窗口标题跟着标签走。切来切去不会把你填了一半的东西弄丢。

## 应用内反馈，可以带截图和录屏

「设置 → 反馈」：先选类型（问题反馈 / 功能建议 / 其他），选完输入框会给一段对应的提示告诉你写什么最有用；正文之外可以留个联系方式（选填）。

**最多可以带 3 个附件**——截图 10 MB 以内、录屏 30 MB 以内、加起来不超过 40 MB。附件存在不公开的存储桶里，最多保留 90 天。

发送失败时会告诉你到底是什么原因（断网 / 发得太频繁 / 附件通道当天满了 / 服务器暂时不可用……），而不是一律让你「检查网络」。附件通道满了的时候，把附件去掉、只发文字是能发出去的。

## 界面语言可以自己选

「设置 → 通用」新增语言选项：跟随系统 / 简体中文 / English。默认跟随系统，所以老用户不会有任何变化。改完重启应用生效，会弹一个对话框问你要不要马上重启。

## 显隐快捷键可以改键

默认还是 ⌥⇧⌘D。想换的话去「设置 → 通用」，点一下直接按你想要的组合键。系统占用的组合（比如 ⌥⌘D）和一些会打架的组合会被挡住；万一新组合注册不上，会自动退回原来那个。

## 鼠标滚轮方向可以单独反转

「设置 → 通用」，**默认关闭**。打开后只反转鼠标滚轮的方向，触控板和妙控鼠标不受影响——这正是很多人从 Windows 过来最别扭的一点：系统里那个「自然滚动」一改，触控板也跟着反了。

## 右键菜单里能看到应用的所有窗口

常驻图标、消息应用图标、抽屉里的应用、Finder 常驻图标——右键打开时，菜单最上面会像系统 Dock 那样列出这个应用的所有窗口：当前最前面的那个打勾，整组都收起来的标个菱形，点一下直接切过去（收起来的会还原）。**抽屉里和消息区应用被最小化的窗口，这是第一次有地方点得到。**

单个窗口的卡片不列——它自己就是那个窗口。

## 「授权」标签页

钨极 1.0 起转为一次性买断（不做订阅），这一版先把授权码的验证做好：本地验签、不联网、不绑设备。**现在仍然完全免费**，在 1.0 之前完成邮箱确认的原始用户永久免费。

## 修复

- **Ghostty 的幽灵卡片**：关掉一个最小化窗口的最后一个标签页后，任务条上会留一张点不动的卡片，要重启任务条才消失。修好了。
- **未读红点不再依赖消息区**：以前只有进了消息区的应用才有红点，而 Messages、Slack、Discord 这类国外的消息应用根本进不了消息区，就永远没有红点。现在红点按「是不是消息应用」来判断，与消息区无关；微信、Telegram 那种「消息区里一个只能唤醒的图标 + 另一张重复卡片」的情况也一并修好了。

---

## 安装

**已经是 0.9.0 – 0.9.5 的话**：什么都不用做，更新会自己找上门；也可以去「设置 → 关于」点「检查更新…」。**辅助功能授权照旧有效。**

**下载安装包**：从[官网](https://tungstenedge.app)下载 `.dmg`，拖进「应用程序」，双击打开。

**Homebrew**：

```bash
brew tap moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**从 0.8.0 或更早升上来？** 那些版本没有经过 Apple 签名，macOS 会把这一版当成另一个应用，旧的辅助功能授权不会生效。先完全退出钨极，打开「**系统设置 → 隐私与安全性 → 辅助功能**」，用「−」按钮**删掉**旧条目（关掉再打开不行），然后重新打开钨极并重新授权。

需要 macOS 12 或更新。通用二进制——Apple 芯片和 Intel 都支持。
