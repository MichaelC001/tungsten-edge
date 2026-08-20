Tungsten Edge v0.9.1 is a small follow-up to the big 0.9.0: **Finder becomes an ordinary app you can uncheck**, and four things about dragging that did not feel right were fixed — most of them in the path from the drawer back onto the taskbar.

If you are on 0.9.0, this is the first update that arrives **on its own** — the update window will offer it, and one click installs it.

---

## Finder can now be unchecked

Finder used to be a permanent exception: always on the taskbar, no right-click option, and it could not go into the drawer. It now uses the same **Keep in Dock** model as every other app.

- The right-click menu has a **Keep in Dock** item, and it is **already checked**, so nothing looks different after upgrading.
- Uncheck it and Finder behaves like any other app: one chip per window while windows are open, and the permanent entry disappears once you close them all. Open a Finder window and it comes straight back.
- Finder can also be **stashed in the drawer** now.
- The messaging zone still does not accept Finder. An icon there stands for an app's main window, which Finder does not have.

## Dropping onto the taskbar no longer paints a black frame

Dragging an icon out of the drawer used to outline the whole taskbar in black. The drop highlight was replacing the glass rim rather than sitting on top of it, and once Liquid Glass became the default that rim turned bright — so the same code started reading as a black border. The highlight is drawn over the rim now.

The drawer direction no longer highlights the bar at all, matching the Dock: the chip making room for what you are carrying is already the feedback.

## The return flight no longer doglegs

Release a chip and it used to fly to a spot slightly off to the right, then jump to where it actually belonged. Letting go unfreezes the bar's width, so the bar re-centres and both panels slide for a fifth of a second — and nothing was telling the flight in progress that its destination had moved. It is told now, from every direction.

## A messaging app in the drawer can be dragged back to its zone

Close WeChat's main window and it keeps running — the dot is still under its icon and it still sits in the messaging zone — but the taskbar has no window to track for it. The rule that decided whether you could drop it there was reading that window list, so the drag was rejected before it ever looked at where your pointer was. It now asks the same question the zone itself asks: will this actually show up once you let go.

## Dragging out of the drawer feels like dragging inside the bar

The two paths were supposed to be identical and were not. The biggest difference was structural: a chip dragged inside the bar flies back to its slot when you let go, while an icon dragged out of the drawer simply teleported into place. It flies now, with the same interruptible flight the bar has.

- **The bar widens the moment the card appears**, instead of snapping open when you let go — so the drag and the release both happen in a layout that is standing still.
- **What you are carrying now cross-fades** when it changes form, instead of a 31pt icon becoming a full card in a single frame.
- **Apps that are not running turn into cards too.** They used to stay a small drawer icon the whole way.
- **Releasing a messaging app back into its zone no longer jumps in size.**

---

## Installing

**Already on 0.9.0?** Do nothing — the update window will find it. Or use *Check for Updates…* in **Settings → About**. **Your Accessibility permission carries over**; the one-time re-authorisation that 0.9.0 needed does not apply here.

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

钨极 v0.9.1 是 0.9.0 那一大版之后的小幅跟进：**访达变成可以取消勾选的普通应用**，另外修好了四处拖起来不对劲的地方，大多集中在「从抽屉拖回任务条」这条路上。

如果你现在是 0.9.0，这是**第一个会自己送上门**的更新——更新窗口会提示你，点一下就装好。

---

## 访达可以取消保留了

访达以前是个全局特例：永远待在任务条上、右键没有相关选项、也不能收进抽屉。现在它和所有应用一样，走同一套**「在程序坞中保留」**模型。

- 右键菜单里多了一条**「在程序坞中保留」，而且默认已经勾上**，所以升级之后你看不出任何变化。
- 取消勾选之后，访达就和普通应用一样：有窗口时一窗一卡，所有访达窗口关掉后那张常驻入口卡消失；再开一个访达窗口，它立刻回来。
- 访达现在也**可以收进抽屉**了。
- **消息区仍然不接受访达**。消息区的图标代表「这个应用的主窗口」，访达没有这种东西。

## 拖回任务条时不再出现一圈黑边

从抽屉里拖图标出来的时候，整条任务条会被描上一圈黑边。原因是投放高亮当初写成「把玻璃那圈亮边整个换掉」，而不是加在它上面；玻璃转正成默认之后那圈边变亮了，同一段代码就显出黑框来。现在高亮改成盖在原来那圈边上面。

另外**抽屉方向干脆不再整条高亮**了，这和原生程序坞一致：图标为你手上的东西让出位置，这本身就是反馈。

## 归位飞行不再拐弯

松手之后图标会先飞到偏右的位置，再跳回它真正该去的地方。因为松手那一刻条宽解冻、整条重新居中，两块面板一起滑 0.22 秒，而正在飞的那个图标没人告诉它终点已经挪了。现在四个方向都会告诉它。

## 抽屉里的消息应用可以拖回消息区了

微信的主窗口一关，它其实还在跑——图标下面照样有运行小圆点，消息区也照样显示它——但任务条这边没有窗口可以跟踪。而判断「能不能放进消息区」的那道闸看的正是窗口清单，于是还没轮到判断你的指针在哪儿，就直接判了不接受。现在这道闸改成问消息区自己问的那个问题：松手之后它到底会不会显示出来。

## 从抽屉拖出来的手感，和条内拖动一致了

这两条路本来就该一模一样，实际不是。最大那处差别是根本性的：在条上拖动的图标松手后会飞回槽位，而从抽屉拖出来的是「啪」地瞬移到位。现在它也会飞了，而且用的是条内那套现成的、飞行途中可打断的飞行。

- **条宽改成「卡片一现身就张开」**，不再等到松手才张开——这样拖动和松手都发生在一个静止的布局里。
- **拎在手里的东西换形状时改成渐变**，不再是 31pt 的小图标一帧炸成整张卡。
- **没在运行的应用也会变成卡片了**，以前全程拎着抽屉里那个小图标。
- **把消息应用释放回消息区时不再突然变大。**

---

## 安装

**已经是 0.9.0 的话**：什么都不用做，更新窗口会自己找到它；也可以去「设置 → 关于」点「检查更新…」。**辅助功能授权照旧有效**，0.9.0 那次的一次性重新授权在这一版不需要。

**下载安装包**：从[官网](https://tungstenedge.app)下载 `.dmg`，拖进「应用程序」，双击打开。

**Homebrew**：

```bash
brew tap moonbai-studio/tungsten-edge
brew trust moonbai-studio/tungsten-edge
brew install --cask tungsten-edge
```

**从 0.8.0 或更早升上来的话**：那些版本没有 Apple 签名，对 macOS 来说这一版等于换了个应用，旧的辅助功能授权不再生效。请先退出钨极，打开「系统设置 → 隐私与安全性 → 辅助功能」，用「−」把旧的那条**删掉**（关开关不管用），再重新打开钨极按引导授权一次。

需要 macOS 12 或更新版本，Apple 芯片与 Intel 通用。
