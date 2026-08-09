# Known Platform Quirks

## Accessibility TCC 身份与发布签名（2026-07-29 实测）

- macOS 的辅助功能授权绑定的是**应用的代码身份**，不只看显示名或 bundle ID。ad-hoc 签名没有稳定的签名者身份，其 designated requirement 落在当前二进制的 `cdhash` 上，**每次重新构建都可能变成一个新身份**。
- 公开发布包目前仍是 ad-hoc（`Scripts/package_release.sh` 的 `codesign --force --deep --sign -`）。覆盖升级后，系统设置里可能留着一条**看起来仍然开着**的旧条目，而当前进程的 `AXIsProcessTrusted()` 依旧返回 `false`。
- 这些失配记录会**持续累积**：2026-07-29 清理 owner 本机时，一次清出 **32 条**同一应用的授权记录。用户看到的那条开着的开关很可能属于早已失效的某一条，所以「关开一次」「删掉重加一条」都可能无效——要把该应用的记录整个清空。
- 反过来，**固定签名身份的授权跨版本有效**：本机固定证书（`macos-dock-cc Local Code Signing`）签的包，`cdhash` 从 `c043dc7a` 变到 `2e84976f`、构建号 9→10，授权依然有效。正式签名（Developer ID）是这个缺陷唯一的根治办法，本仓库当前尚未具备资格。
- **不要从只读卷或 App Translocation 临时路径请求辅助功能权限**：那会在系统里留下一条指向随时消失的副本的死记录。先移入 `/Applications` 再注册。判据是**卷是否只读**而不是「路径在 `/Volumes` 下」——后者会误伤把应用装在移动硬盘上的用户。读写型磁盘映像是明确接受的漏拦边界。
- Gatekeeper 放行 / 公证状态与 Accessibility 授权是两套独立机制；清除 quarantine 修不了旧 TCC 身份。
- 外部判断权限有没有真正生效：`lsappinfo list | grep "pid = <pid>"` 报 `type="UIElement"` 说明应用已进入正常的无程序坞图标运行态。反过来 `Foreground` **只说明尚未进入**，不等于未受信——搬家引导态和权限恢复态都是「已受信但仍是 Foreground」。系统设置里的开关状态不作数。
- 辅助功能列表里的「−」按钮在应用运行时是灰的，必须先退出应用才能删条目。

## 窗口与观察

- `CGWindowID` 在最小化后会从默认窗口列表里消失。
- Accessibility 通知在某些应用中不可靠，尤其微信、飞书。
- Finder 进程长期存在，不等价于“有 Finder 窗口”。
- Finder 具体窗口名可通过 `CG` / `AX` / AppleScript 取得；如果 UI 只显示 `访达`，优先怀疑当前观察链路丢了窗口级信息。
- Finder 激活不能轻易退回到 app-level activate，否则可能带出错误窗口或多个窗口。
- 某些 app 创建窗口时标题先为空，稍后才填入真实标题。
- `com.apple.systempreferences` 是反例：真实主窗口完全就绪后仍可能表现为 `AXWindow` / `AXStandardWindow` + 空标题；空标题不只是一种启动瞬态。
- `CG` 的 `disappeared` 事件会带着旧 `cgWindowID` 回流；验收逻辑不能把这类事件当成“当前仍可见窗口”。
- 当前采样里，飞书可能出现 `CG` 可见但标题为空、同时 `AXWindows` 为空的时刻。
- `AX` 可能暴露系统内部窗口、小组件、扩展窗口或辅助进程窗口；这些对象看起来像窗口，但不一定是用户想在任务条里操作的窗口。
- 放宽 `AX` 采样范围时必须先经过窗口准入 policy。否则假窗口进入状态后，会被最小化 / 隐藏 / 临时消失保位规则放大，造成任务条突然出现几十或上百个条目。
- `System Events` / App 级窗口枚举更接近“用户正在使用哪些 app 窗口”的产品直觉；v2 当前正式实现不用 shell `osascript`，而是用 `NSWorkspace` + `AXWindowReader` 做同类 app-window inventory。
- 底层 `CG` / `AX` 扫描可能同时出现两种失败：放得太宽会收进假窗口，收得太紧会漏掉真实用户窗口。当前主线已改成用户 app 窗口清单优先，再用底层信号补证据。
- 透明窗口只应可靠过滤 `alpha == 0` 的情况；不要用“视觉上透明”这种不稳定判断做强过滤。
- **几乎每个常规应用都常驻着一批无标题 layer-0 窗口**（2026-08-02 实测 owner 机器：微信 8、Photoshop 7、飞书 6，WPS / QQ / ChatGPT / Dia / Obsidian / 访达 / Tailscale 各 5；同一时刻在屏的 9 个候选则全部有标题）。它们平时不在屏，只在启动、弹窗、动画等时刻短暂上屏——所以由它们引起的故障天然是**偶发**的，复现时要先制造"让它上屏"的条件。
- **`kCGWindowName` 需要「屏幕录制」权限，本项目按产品决策不申请**（`Docs/27`），所以 `DockWindowEligibilityPolicy` 的标题分支在任何 **CG-only 调用点**（`subrole` 传 nil、事后不做 AX 形状复核）都不可靠：要么恒为 filter，要么只剩策略里那条飞书无标题放行能通过，等于击穿整套过滤。该策略只能配合 AX 数据使用；CG-only 判定要么自己先要求非空标题，要么改用任务条快照里已认过的 `cgWindowID`。2026-08-02 「最小化时飞书主窗口被带出来」就是这么来的。
- 只有通过准入 policy 的可信窗口，才应该享受 keep-slot 和 `disappeared` retention。
- `AXUIElementCopyAttributeValue` 可能被单个 App 卡住；inventory 读取使用 100ms per-app messaging timeout 和 12 路并发，慢 App 连续 unread 30 轮后会进入 degraded fallback。
- **WPS 重启后整组卡缺失的 timeout 猜测尚未坐实**（2026-08-05）。同一现场两进程 A/B：默认 100ms 和 untimed seed 都对 pid 40474 读到 raw=2 / eligible=2 并 admit，对 pid 47258 读到 success/raw=0；两臂没有 unread，默认臂也正常显示两张窗口卡。本次只能判定「未复现」，不能把历史那次缺卡归因于 100ms。后续复发先开 `InventoryLog` 看逐 PID `admissionProbe`，不要先改超时或补扫轮次。
- 调试壳本身如果被准入任务条，会因为内容变化触发窗口尺寸或观察签名变化，造成同一自家窗口被误认成多个条目。当前主线已直接过滤 `com.caye.macosdockcc.v2`，避免任务条自我污染。
- 长时间空闲 / 睡眠 / 过夜后，6 秒身份记忆会自然过期。不能依赖短记忆认回窗口；必须把当前任务条 `DockSnapshot` 当作长期座位图来对账。
- 同一个真实窗口在恢复或跨屏状态变化后，frame 可能发生较大偏移；如果同进程同应用下标题唯一，可以用唯一标题认回旧座位。多个同名候选时不能猜。
- 浏览器、Illustrator、Photoshop、Finder、WeChat、Terminal、Codex 等应用会暴露不同粒度的标题或位置变化；这些应作为通用身份规则的验收样本，不应变成应用白名单。

## LaunchServices 与同 bundle ID 多包应用（2026-08-01 实测）

- `com.lemon.lvpro` 同时注册外层 `/Applications/VideoFusion-macOS.app` 与两个嵌套 `.app`；嵌套主体和 TrayHelper 均声明 `LSUIElement=1`，TrayHelper 可单独以 `.accessory`、无窗口运行。
- `NSWorkspace.OpenConfiguration.allowsRunningApplicationSubstitution` 默认开启，允许不同 URL 的已运行实例替代所选应用；`createsNewApplicationInstance=true` 则忽略该设置并强开新实例，不能拿它当通用修复。
- 修复前直接对外层主体调用默认 `openApplication`，completion 实际返回嵌套 `VideoFusion-macOSTrayHelper.app` 且无错误；同一目标关闭 running substitution 后返回外层主体本身。该类问题必须按 canonical bundle path 取证，pid 只是一轮会话的临时值。

## 状态栏菜单与 macOS 集成限制（2026-06-30）

- `SMAppService.mainApp` 登录项接入只在 macOS 13+ 可用；macOS 12 菜单里应显示为不支持，不要无保护调用 13+ API。
- 登录项状态不是二态。除了 `unsupported` / `off` / `on`，还必须处理 `requiresApproval`：注册成功但仍需用户到系统设置批准，这不是失败。
- 本机 SDK 已确认 `SMAppService.openSystemSettingsLoginItems()` 标注 `macOS 13.0+`，仍必须用 `#available(macOS 13.0, *)` 包住，因为项目最低部署目标是 macOS 12。
- 沙箱 App 不能直接修改系统 Dock 偏好或重启 Dock。`NativeDockPreferencesService` 必须通过 `SecTaskCopyValueForEntitlement("com.apple.security.app-sandbox")` 检测沙箱；沙箱为 true 时不要执行 `defaults write com.apple.dock` 或 `killall Dock`。
- 当前系统 Dock 写入面向非沙箱 GitHub/Homebrew 分发，两条路径互不混用（owner 2026-07-30）：菜单显隐命令只写 `autohide` 后重启 Dock（严格等价 ⌥⌘D，不碰 `autohide-delay`）；滑块按档写入，常驻档只写 `autohide=false`，其余写 `autohide=true` + `autohide-delay`（不唤醒档落 999）后重启 Dock。读永远走 `CFPreferences`，写永远走 `/usr/bin/defaults` 子进程。
- 每次写入都以 `killall Dock` 收尾，因此滑块必须**松手才提交**，不能逐格触发；键盘 / VoiceOver 调整走不到 `mouseDown`，要有 debounce + 菜单关闭时 flush，且三个触发源必须原子去重（`PreferenceSliderCommitTracker`）。
- `defaults` + `killall` 是多步非事务序列，写完必须重读系统真值再决定本地镜像落什么值；**不能一律「失败就回滚」**——写成功但读不回来时回滚会让 UI 显示得和已生效的系统设置相反（四象限见 `AutoHideToggleMenuModel.resolvedStoreDelay`）。只有写失败才弹错误框。
- 「打开系统 Dock 设置…」只通过 `NSWorkspace.open` 跳转，不写偏好、不重启 Dock，因此不走写入路径的沙箱门控。首选 `x-apple.systempreferences:com.apple.preference.dock`；失败后打开 `/System/Library/PreferencePanes/Dock.prefPane`，由 macOS 12 的 System Preferences 或新版 System Settings 接管。不要为此启动 `/usr/bin/open` 子进程。

## 面板几何与 `visibleFrame`（2026-07-01）

- `NSScreen.visibleFrame` 会随系统 UI 可用区变化：底部 Dock 显示/隐藏会改变底部可用区；左/右 Dock 常驻会改变 `visibleFrame.minX` / `visibleFrame.maxX`。
- Cmd+Opt+D 显示或隐藏系统 Dock 时也会触发 `visibleFrame` 变化。底部任务条、胶囊、抽屉如果用 `visibleFrame` 贴底或横向 clamp，会出现原生 Dock 一唤醒就上移/变窄的错觉。
- 底部三面板和跨面板拖动载体应锚定到物理屏幕 `screen.frame`：底边用 `screen.frame.minY`，横向 clamp 也按 `screen.frame`。这套 UI 有意贴屏幕物理底边，不避让系统 Dock 常驻占位。
- `visibleFrame` 仍适合表达菜单栏/可用区上限。抽屉最大高度继续受 `visibleFrame.maxY` 与 `screen.frame.maxY - safeAreaInsets.top` 的较小值限制，避免顶到菜单栏或刘海安全区。
- 菜单栏自动隐藏会让 `visibleFrame.maxY` 改变；在无刘海外接屏上，抽屉最大高度仍可能随菜单栏显隐跳变。这是已知边界，不等同于底部 Dock 显隐导致面板整体移动的问题。

## Tungsten Edge 自动隐藏与多屏底边探测（2026-06-30）

- Tungsten Edge 的自动隐藏滑杆语义是“底边唤醒等待时间”，不是“鼠标离开后多久隐藏”。有限值范围为 `0.1s...3.0s`；`不唤醒` 表示会隐藏，但底边不启动唤醒计时。
- 鼠标离开 Dock / 胶囊 / 抽屉后，idle hide 延迟固定为 `0.2s`。不要把它重新绑回滑杆值。
- 隐藏态也必须持续做底边探测；不能依赖 Dock 面板可见或鼠标进入面板区域才启动唤醒。
- 底边热区与多屏切换共用同一探测入口：当前屏底边直接走唤醒逻辑；另一块屏幕底边先经过约 `0.35s` 驻留切屏，切屏后再从 0 开始计算唤醒延迟。
- 多显示器策略 UI 已移除，运行时固定为多屏自动切换语义。不要重新读取旧的 `displayMode` defaults key 来决定底边行为。

## 全屏下的系统 Dock：四条配置路都阻止不了底边唤出（2026-08-05 实测）

> 背景：owner 想要「全屏时鼠标移到最下方，出来的不是 Dock 而是钨极」。功能本身做得出来（面板确实能画在全屏空间上），但**系统 Dock 会同时被唤出并盖在钨极上面**。下面四条路逐条实测走死，结论沉淀在这里，避免下一轮从头再问一遍。封存代码在 `parked/fullscreen-edge-wake`。
>
> **2026-08-08 最终结论：非 root 的 session `CGEventTap` 也阻止不了。** `codex/fullscreen-edge-filter-spike` 先用合成事件测到全屏中央触底能从 `y=981` 夹到 `y=980`、钨极 `20/20` 唤醒，但 control 本身没有唤出 Dock，所以那轮不能下结论。随后用**同一个固定证书 Release 二进制**（SHA-256 `b333adeeab62830c6e500970c636a158015505cec70608027237dd4b98a78fa5`）完成真实物理 A/B：control 下钨极先在较宽的既有热区出现，继续压到物理底边后系统 Dock 出现并盖住它；filter 下 event tap 全程 enabled，30 个底边 episode 的应用层光标最高值都被夹在 `y=980.0–980.9`，证明过滤确实生效，但真实触底仍 `20/20` 唤出 Dock。结论是 WindowServer / Dock 在 session tap 之前已经消费了原始 HID 边缘信号；再早的 `kCGHIDEventTap` 需要 root，不符合公开应用约束。过滤器保持 `#if DEBUG`、默认关闭、只留实验 worktree，未进主线。不要再重试 session tap 或拿合成事件的 Dock `0` 当成功证据。

**实测事实**（owner 实机 + CGWindowList / 二进制探针）：

- **`autohide-delay` 管不到全屏。** 该键为 `999`（钨极滑杆的「不唤醒」档）时，桌面上确实不再唤醒，但全屏下贴底边 Dock 照样滑出。两条路径是分开的。
- **Dock 在全屏下的唤出触发区贯穿整条屏幕底边**，不只是 Dock 自身那段宽度。在远离 Dock 本体的最左 1/4 屏宽处贴底边，Dock 同样出来 —— 所以靠横向位置与钨极热区错开是不可能的。
- **窗口层级：Dock 可见窗口 `kCGWindowLayer == 20`，钨极所有面板是 `.floating`（layer 3）**，拖动载体是 `.popUpMenu`（101）。Dock 一旦出现就压在任务条上面。
- **钨极热区比 Dock 的物理边缘触发区高。** control 实测鼠标下移时钨极先出现；再向下几个像素压到物理底边，Dock 才出现并覆盖它。这不是 filter 造成的偏移，而是两套原生触发范围本来就不同。session filter 只夹最后 `1pt`，没有改变钨极的既有提前唤醒距离，但仍来不及阻止 Dock。
- **`autohide-time-modifier` 能压住全屏唤出**（调到 30 后全屏下 Dock 实际不再出现），但两条限制让它不可用：① 全局生效，桌面上主动召唤 Dock 也跟着变慢；② **值被 Dock 缓存在进程内存里，只在 Dock 启动时读一次** —— 改完不 `killall Dock` 完全无效（实测：plist 改回 1 后行为纹丝不动，直到重启 Dock）。因此「进全屏调慢、退出调回」必然每次闪一下屏，不可接受。
- **`com.apple.dock.prefchanged` 这个分发通知名确实存在于 Dock 二进制，但对该键无效**：发完通知行为不变，仍需重启。不要再拿它当「免重启改 Dock 偏好」的通道试第二次。
- `com.apple.dock` 当时全部 32 个键里，没有任何一个与全屏唤出相关。

**为什么没有偏好项**（读 Dock 二进制得出，非运行时实测）：Dock 里有 `setShowDock:fullscreenMode:` / `uiModeFullscreenMode` / `setUiModeFullscreenMode:`，指向 `SetSystemUIMode` 那套。全屏下 Dock 处于 **suppressed（藏起来但可唤出）** 还是 **hidden（藏起来且不可唤出）**，由**当前全屏的那个 app** 决定，不由任何偏好决定。而 presentation options 只对**活跃 app** 生效 —— 钨极是 `.accessory` 且设计上永不抢焦点，所以够不着；让它去抢焦点比 Dock 冒头糟得多。

**明确不走的路**：Dock 内部有 `setAutoHideSpeed:`，但那是它自己的 ObjC 方法，外部只能去戳 `com.apple.dock.server` 私有服务。公开发布的 app 不碰 —— 一次系统更新就可能失效。

**尚未验证的推论**：把钨极面板层级抬过 20 应该能让它压住 Dock，但未实装验证。「Dock 会从钨极上沿露出约 12pt」是估算（`tilesize` 40 推得条高约 64pt，钨极中档 52pt），**没有实测** —— Dock 隐藏时那个 layer-20 窗口是铺满整屏的容器窗口，量不到条本身的高度。

## 进全屏时任务条闪一下：输入投递前隐藏已修复（2026-08-09）

> v0.7.6 的现象是从非全屏切到原生全屏时，任务条**先消失 → 又冒出来一下 → 再消失**。当前实现对标准绿灯和精确 `Control-Command-F` 在输入投递前同步隐藏，owner 的 TextEdit 固定证书 Release 验收为 `0/3 + 0/3` 肉眼闪烁。

**为什么旧路线都无效**：`activeSpaceDidChange` 即使把判定从 21ms 压到 0ms，通知仍晚于 WindowServer 合成；撤掉 `.fullScreenAuxiliary` 与 control 的重叠约 `769ms / 776ms`，无差别；`AXWindowCreated/Resized` 能在全屏 CG 窗口前约 18ms 完成分类，但主线程 `orderOut` 仍错过过渡快照，约 345ms 重叠。不要重试更快 Space verdict、collection behavior 或同一 AX 通知链。

**有效信号是原始用户意图**：session `.defaultTap` 在目标应用收到标准绿灯或 `Control-Command-F` 之前命中缓存的聚焦窗口/全屏按钮几何，主线程完成 dock、capsule、drawer、folder popup、tooltip 的 `orderOut` 后才放行原事件。随后以 generation-guarded pending 等 Space/CG/AX 确认，1.2s 未确认则恢复原 edge-auto-hide 可见性。机器仍能量到绿灯样本约 `10–90ms` 的 CG 残留，但 owner 在看到数据后明确把发布判据改为肉眼 0 闪烁；这是验收口径反转，不是机器判据通过。

**事件 tap 的平台边界**：tap 在专用线程 `.commonModes` 上运行；500 个非目标按键的开关 A/B 为 disabled `p95 0.191ms / p99 0.258ms`、enabled `p95 0.202ms / p99 0.242ms`，两组 `500/500`、零 disable。Secure Input 下系统不投递键盘事件，所以只能依赖后续常规全屏判定；绿灯不受影响。功能默认开启，设置可关，`DOCK_FULLSCREEN_INTENT=0` 优先。

**全屏 Space 互切已用状态 hold 修复，不是输入拦截**：早期探针开 `0/12`、探针关 `0/4` 的肉眼样本不能证明没有闪烁；fresh 进程随后稳定复现，遥测坐实路径为 `.fullscreen -> Space CG false -> SHOW -> AX true -> HIDE`，三次可见脉冲约 `11.3 / 3.4 / 2.2ms`。当前代码在已经确认 `.fullscreen` 时，遇到应用激活或 Space 通知先建立带代次的 hold，吞掉转场中的 false CG/AX；Space 通知后等 `120ms` 再用 CG + AX 作最终确认。owner 在清理失败实验后的 fixed-certificate Release 上复验：三指与 Control-arrow 全屏互切均不闪，全屏返回普通 Space 正常显示任务条。没有加入三指/方向键专用事件拦截。

**普通 Space -> 已有全屏 Space 仍未修**：managed-space 预测实验能在 `activeSpaceDidChange` 前约 `35ms` 同步 `orderOut`，目标 AX 全屏也在通知后约 `0.2–1ms` 可读，但 owner 仍稳定观察到闪烁，说明这两个信号都晚于 WindowServer 的转场快照；实验代码已删除。为排除“合并时删掉了有效代码”，2026-08-09 又原样恢复 `13:00` 的 SpacePrediction Release（原编译二进制 SHA-256 `819edbd2459e36f8af0763cd2d517763203d14009da909afa6da84cd4048da3b`）严格回放：三指 `3/3`、Control-arrow `3/3` 闪；6 次日志均先 hide、后 Space 通知，提前量 `27.8–35.3ms`，中间没有 show。画面闪烁因此是更早固化进 WindowServer 转场快照，不是合并后重新显示。一次性探针对三指切 Space 的 14 次真实 `id64` 变化均未取得提前手势事件；Control-arrow 则约早于 Space ID 变化 `548–575ms`，但尚未实现键盘专用修复。不要把 full-to-full hold 泛化成普通到全屏已修，也不要重试 managed-space/app-activation 预测。

**顺带坐实的 SkyLight 事实**（与上面成败无关，是可复用的零件）：

- **managed space `type == 4` = 原生全屏空间，`type == 0` = 普通桌面空间。** 每 80ms 采样、只记变化，抓到三个完整周期 `0 → 4 → 0`
- **该信号按显示器隔离**：全程第二块屏恒为 `0`，只有任务条所在屏在跳 —— 多屏方案可以依赖它
- **调用开销 0.132 ms/次**（`SLSCopyManagedDisplaySpaces`，200 次 26.4ms），可以放心用在事件路径上
- 符号在 `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`：`SLSMainConnectionID` / `SLSCopyManagedDisplaySpaces`（旧名 `CGSMainConnectionID` / `CGSCopyManagedDisplaySpaces` 也还在）；字典键 `Display Identifier` / `Current Space` / `type`；**显示器必须按 `CGDisplayCreateUUIDFromDisplayID` 的 UUID 匹配，不能按数组顺序**
- 它只能当**补充**信号：无边框全屏（游戏 / 网页全屏）不创建 type 4 空间，仍需 CG / AX 兜底

## 原生标签组（NSWindow tabbing）与“哪个标签可见”的判定（2026-06-14 实测，Ghostty）

> 这是“同 app 多标签合并”功能里反复踩坑后挖出来的平台事实。Obsidian 那份是产品/设计视角，这份是工程视角，写代码时按这条来。

- **原生 NSWindow tabbing（Finder / Ghostty 类）= N 个真实 NSWindow**：同 `pid` + 逐像素相同 frame，各有独立 `cgWindowID`、各 `AXStandardWindow`。浏览器标签则是 1 个 NSWindow 自绘，天然就一个窗口。要合并的是前者。
- **非当前标签在 AX 里报告为“最小化”（`min=1`）**：一个标签组里同一时刻只有当前可见标签 `min=0`，其余后台标签全报 `min=1`。这不是真的最小化，是 tabbing 的实现细节。
- **切标签时 AX 的状态严重滞后/不可靠，不能用它判可见标签**：实测 ① 切走的老标签 `min` 会被 AX **持续误报为 0 长达 ~4 秒**（AX 自身就报错，不是轮询慢）；② 老标签的 `Miniaturized` 通知**根本不发**；③ 新标签的 `Deminiaturized` 通知**时有时无**（赌它做事件驱动会出 bug）。过渡期“两标签同时 `min=0` / `foc=1`”，**没有任何瞬时 AX 字段能区分谁可见**。
- **可靠信号 = `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`**：后台标签是被 order-out 的独立 NSWindow，**不在 on-screen 列表**；每个标签组恰好留 **1 个**在屏 = 当前可见标签。实测 Ghostty 38 窗 → on-screen 仅 2（两组各 1）。合成层真相，切标签即时更新，无 AX 滞后。判“标签组里谁可见”用它。
- **CG bounds 与 AX bounds 可能不同**：实测同一 Ghostty 标签，CG 报宽 1005/874，AX 报 1191。所以**分组用 AX bounds**（与 `StripItem.tabGroupKey` 一致），**只用 CG 判 `cgWindowID` 是否在屏**——两者别混用。
- 当前实现：`AppTracker.rebuildSnapshot` 对“同 frame ≥2 成员”的标签组改用 on-screen 判可见性（不在屏即视为最小化），普通单窗口仍走 AX；前台 0.5s 轮询比对 on-screen 集合发现切标签（AX 完全不报时的即时触发）。`CGWindowListCopyWindowInfo` 在无屏幕录制权限时拿不到标题，但 `pid` / `number` / `bounds` / `layer` / on-screen 都可用，足够本判定。

## 激活/前台切换的时序陷阱（2026-07-03 实测，激活闪根治过程沉淀）

> 完整调试过程见 `Docs/22` §12；硬护栏见 AGENTS.md「Minimize returns focus…」激活闪条目。

- **`NSWorkspace.frontmostApplication` 是通知驱动缓存，SkyLight（`_SLPSSetFrontProcessWithOptions`）切前台后滞后 0.4–1.5s**。动作决策路径（toggle 规划、最小化预切 guard）读它会误判；**新建 `NSRunningApplication(processIdentifier:)` 实例读 `isActive` 是即时的**，决策一律用后者。
- **对打盹（App Nap）App 的任何 AX 问询可阻塞 400–900ms**：`inventoryWindows`（0.5s messaging timeout）、`kAXMinimizedAttribute` 读取、`_AXUIElementGetWindow` 都会卡。凡在用户点击的即时路径上，能用快照 / CG 数据就不要现场问 AX——这条空窗曾是激活闪的根因。
- **打盹 App 的窗口会从 `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 临时消失**（连"当前前台 App 刚激活的窗口"都可能缺席几秒）。按 on-screen 列表反查 cgWindowID 不可靠；快照里的 `record.cgWindowID` 才是稳定来源。
- **抢顶型 App（Ghostty、Chromium 系：Chrome/Dia）在自己仍是活跃 App 期间，若别的窗口被 AXRaise 盖到它上面，会在 ~+450ms 把自己的窗口浮回顶层**；良性 App（Finder/Safari/微信/飞书/PS/AI…）不会。这就是为什么"闪不闪取决于从哪个 App 切走"。
- **对仍最小化的窗口发 SkyLight make-key 事件，App 会把键盘焦点落到它的可见兄弟窗口上**（Chrome/访达实测）。最小化恢复后必须对目标窗口 `kAXMainAttribute=true` 纠正 App 内部焦点，否则输入焦点和 AX `kAXFocusedWindow` 都停在兄弟窗口。
- **App 被切成前台进程时若没有 key 窗口（目标窗口仍 order-out/最小化），AppKit 会自动把该 App 最上面的可见窗口提为 key 并持久抬到旧前台之上**（2026-07-05 探针，访达/微信/Dia 一致）。裸 psn 切换（不发 make-key）拦不住，`kCPSNoWindows (0x400)` 也拦不住——提拔发生在 App 侧而非 WindowServer 侧。要恢复最小化窗口且不带起兄弟：**先 unminimize、后切前台，两步微秒级相邻、中间零 AX 问询**（wid 用快照值）；对刚 unminimize 的窗口立即发 make-key 会正确落在它身上，不再错落兄弟。见 `Docs/22` §13。

## NSRunningApplication(processIdentifier:) 对活进程瞬时返回 nil（2026-07-21 实机确认；2026-07-25 稳定线恢复）

> 4.5 阶段修复 `AppTracker.reconcile()` 批量误删时沉淀的平台事实。

- **`NSRunningApplication(processIdentifier: pid)` 会对活进程瞬时返回 `nil`**：该 API 解析自 LaunchServices，不是直接查询进程表。实测飞书、Obsidian 等应用在正常运行期间会触发此现象——进程明明活着，`NSRunningApplication` 却返回 `nil`，`.isTerminated` 也无法读取。
- **误判后果是整批删除**：`reconcile()` 的批量路径据此判死 pid 后，会一次性删掉整个 `AppEntry` 连同其下所有座位（`WindowEntry`），绕过逐座位对账的宽限期（`closedReapGrace`）、幽灵保护（`PhantomSeatDecision` 五门槛）和逐座位释放日志。
- **之后 `scanNonAdmittedApps()` 把同一 pid 以全新座位 token 重新准入**，叠加 `StripOrderStore` 的 5s 缺席宽限，导致旧 token 和新 token 同时渲染——一扇窗出现两张卡（历史实测：微信 ×35、Telegram ×26 的重复爆发均由此引起）。
- **正确判活用 POSIX `kill(pid, 0)`**：返回 0 = 进程存活；返回 -1 且 `errno == ESRCH` = 进程已死；`EPERM`（进程存在但无权限发信号）及 `EINTR`/`EINVAL`/`EAGAIN` 等所有其他 errno = 保守判活。实现见 `Platform/AppTracking/ProcessLiveness.swift`，只依赖 Darwin，不回退任何 LaunchServices API。
- 此修复曾在旧管线以 `5f57a75` 提交过一次，在 `ef50008` 重写中丢失。4.5 阶段在稳定线重新实现为共享类型，不再内联到 `AppTracker` 中。
