Tungsten Edge v0.9.2 is about one thing: **when a new version is out, Tungsten Edge now tells you** instead of waiting for you to go and check.

---

## Updates find you now

Tungsten Edge has checked for updates on its own since 0.9.0, but in practice you only ever heard about a new version by clicking *Check for Updates…* yourself.

- **New versions now come to you.** You no longer have to go looking.
- **A new version leaves a mark you can see.** A small dot appears on the menu-bar icon, and the menu row becomes **Install 0.9.3…** with a red dot. Both stay put until you install or skip that version — closing the update window no longer wipes the reminder.
- **The update window still comes to the front by itself, but only once per version.** Tungsten Edge has no Dock icon, so an update window that does not come forward opens behind everything and is never seen. Being interrupted about the *same* version every few hours would be worse, so after the first time the two dots carry it quietly.

Nothing else in the app changed in this release.

---

## Installing

**Already on 0.9.0 or 0.9.1?** Do nothing — the update window will find it, or use *Check for Updates…* in **Settings → About**. **Your Accessibility permission carries over.**

**Download the installer**: grab the `.dmg` from the [official website](https://tungstenedge.app), drag it into Applications, and double-click.

**Homebrew**:

```bash
brew tap moonbai-studio/tungsten-edge
brew trust moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**Coming from 0.8.0 or earlier?** Those builds were not signed by Apple, so macOS treats this one as a different app and your old Accessibility permission will not apply. Quit Tungsten Edge, open **System Settings → Privacy & Security → Accessibility**, **remove** the old entry with the「−」button (toggling it off and on is not enough), then reopen and grant it again.

Requires macOS 12 or newer. Universal — Apple silicon and Intel.

---

钨极 v0.9.2 只做了一件事：**有新版本时，钨极会主动告诉你**，不用再自己去点「检查更新」。

---

## 新版本现在会自己找上门

钨极从 0.9.0 起就会自己检查更新，但实际上你多半只有自己点「检查更新…」时才知道有新版。

- **有新版本会主动推送给你**，不用再自己去查。
- **有新版时会留下看得见的记号**：菜单栏图标上多一个小点，菜单里那行变成 **「安装 0.9.3…」** 并带一个红点。两个记号会一直留着，直到你装了或跳过这一版——关掉更新窗口不再把提醒一起抹掉。
- **更新窗口仍然会自己跳到最前，但每个版本只跳一次**。钨极没有程序坞图标，更新窗口不主动跳到前面就会开在所有窗口背后，等于没提示；但同一个版本每隔几小时打断你一次更糟，所以第一次之后就交给那两个记号安静地提醒。

这一版没有改动其它功能。

---

## 安装

**已经是 0.9.0 或 0.9.1 的话**：什么都不用做，更新窗口会自己找到它；也可以去「设置 → 关于」点「检查更新…」。**辅助功能授权照旧有效。**

**下载安装包**：从[官网](https://tungstenedge.app)下载 `.dmg`，拖进「应用程序」，双击打开。

**Homebrew**：

```bash
brew tap moonbai-studio/tungsten-edge
brew trust moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**从 0.8.0 或更早升上来的话**：那些版本没有 Apple 签名，对 macOS 来说这一版等于换了个应用，旧的辅助功能授权不再生效。请先退出钨极，打开「系统设置 → 隐私与安全性 → 辅助功能」，用「−」把旧的那条**删掉**（关开关不管用），再重新打开钨极按引导授权一次。

需要 macOS 12 或更新版本，Apple 芯片与 Intel 通用。
