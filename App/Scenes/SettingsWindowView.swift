import AppKit
import SwiftUI

struct SettingsWindowView: View {
    static let contentWidth: CGFloat = 560

    /// 公开仓库主页。**只给「求 Star」用**——用户可见的「去下载」永远指向官网
    /// （2026-08-13 起 GitHub release 页不再附安装包，指过去是个空页面），
    /// 别顺手把下载入口也改到 GitHub 来。
    static let repositoryURL = URL(string: "https://github.com/moonbai-studio/tungsten-edge")!

    @ObservedObject var store: AppSettingsStore
    @ObservedObject var coordinator: SettingsCoordinator
    @ObservedObject var licenseStore: LicenseStore

    var body: some View {
        ScrollView(.vertical) {
            SettingsWindowContent(store: store, coordinator: coordinator, licenseStore: licenseStore)
        }
        .frame(width: Self.contentWidth)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 用户去系统设置勾完登录项再切回来，状态得跟着变。
            Task { @MainActor in
                _ = await coordinator.refreshLaunchAtLoginState()
            }
        }
    }
}

struct SettingsWindowContent: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject var coordinator: SettingsCoordinator
    @ObservedObject var licenseStore: LicenseStore

    @State private var presentedAlert: SettingsAlert?
    @State private var subscriptionEmail = ""
    @State private var licenseKeyInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection(String(localized: "General")) {
                launchAtLoginRow
                hotKeyRow
                scrollReverserRow
            }

            Divider()

            settingsSection(String(localized: "Taskbar")) {
                settingRow(note: String(localized: "Adds a spot on the taskbar for parking files. Dropping a file there doesn’t move or copy it — Tungsten Edge just remembers where it lives.")) {
                    Toggle("Show Shelf", isOn: binding(get: { store.showShelf }, set: store.setShowShelf))
                }

                settingRow(note: String(localized: "When off, moving the pointer across the taskbar no longer shows app names.")) {
                    Toggle(
                        "Show app name on hover",
                        isOn: binding(get: { store.hoverStyle.isExpressive }) {
                            store.setHoverStyle($0 ? .standard : .quiet)
                        }
                    )
                }

                settingRow(note: String(localized: "Lifts the bottom edge of a screen-filling window above the taskbar. This resizes other apps’ windows, so it is off by default.")) {
                    Toggle(
                        "Keep maximized windows above the taskbar",
                        isOn: binding(get: { store.windowLiftEnabled }, set: store.setWindowLiftEnabled)
                    )
                }

                Picker("Taskbar Size", selection: binding(get: { store.dockSize }, set: store.setDockSize)) {
                    ForEach(DockSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // 「高级」= 需要额外能力、默认就对、基本不用碰的开关。放这里不是为了藏，
            // 而是让主设置面只留日常会调的东西；真想拒绝这个能力的人找得到（owner 2026-08-09）。
            settingsSection(String(localized: "Advanced")) {
                settingRow(
                    note: String(localized: "To keep the taskbar from flashing when you switch into full screen, Tungsten Edge has to hide it before your input reaches the app. It therefore watches global left-clicks, key presses and trackpad gestures, and recognizes only four of them: the window’s green button, Control-Command-F, Control-Left/Right arrow, and a three-finger horizontal swipe. What you type is never recorded, logged, or sent anywhere. Turning this off disables the watching completely.")
                ) {
                    Toggle(
                        "Predict full-screen transitions to prevent taskbar flicker",
                        isOn: binding(
                            get: { store.fullscreenIntentEnabled },
                            set: store.setFullscreenIntentEnabled
                        )
                    )
                }
            }

            Divider()

            settingsSection(String(localized: "License")) {
                licenseRow
            }

            Divider()

            settingsSection(String(localized: "About")) {
                aboutRow
                subscriptionRow
                githubStarRow
            }
        }
        .padding(28)
        .frame(width: SettingsWindowView.contentWidth, alignment: .leading)
        .alert(item: $presentedAlert) { alert in
            guard let openButtonTitle = alert.openButtonTitle, let openURL = alert.openURL else {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text(openButtonTitle)) { NSWorkspace.shared.open(openURL) },
                secondaryButton: .cancel(Text("Later"))
            )
        }
    }

    @ViewBuilder
    private var launchAtLoginRow: some View {
        // 状态恒来自 `LaunchAtLoginService`，不读 `AppSettingsStore` 的镜像——
        // 用户随时可能在系统设置里改掉它。
        let presentation = LaunchAtLoginMenuPresentation(state: coordinator.launchAtLoginState)
        Toggle(
            presentation.title,
            isOn: Binding(
                get: { presentation.isChecked },
                // 走和菜单同一个纯决策，别让两处对四态各有一套理解。
                set: { _ in
                    guard let enable = LaunchAtLoginMenuModel.requestedEnabledValue(
                        afterSelecting: coordinator.launchAtLoginState
                    ) else { return }
                    if case .failure(let error) = coordinator.setLaunchAtLogin(enable) {
                        presentedAlert = SettingsAlert(
                            title: String(localized: "Couldn’t Change Open at Login"),
                            message: error.localizedDescription
                        )
                    }
                }
            )
        )
        .disabled(!presentation.isEnabled)

        if presentation.showsSettingsItem {
            Button {
                coordinator.openLoginItemsSettings()
            } label: {
                Label("Open Login Items Settings…", systemImage: "arrow.up.forward.app")
            }
        }
    }

    /// 显隐任务条快捷键：录制框 + 自定义过才出现的「恢复默认」。行高恒定
    ///（录制态只换文案不换尺寸，按钮出现在同一行内），所以不用给
    /// `SettingsWindowController.sessionSubscriptions` 加 sink。
    @ViewBuilder
    private var hotKeyRow: some View {
        settingRow(note: String(localized: "Toggles the taskbar between always visible and your last auto-hide delay. Default: ⌥⇧⌘D.")) {
            HStack(spacing: 10) {
                Text("Show/hide taskbar shortcut")
                Spacer()
                HotKeyRecorder(
                    currentGlyphs: store.edgeToggleShortcut?.glyphs
                        ?? GlobalHotKeyShortcut.edgeAutoHideMode.displayGlyphs,
                    onRecord: { applyShortcut($0) },
                    onRejectKey: {
                        presentedAlert = SettingsAlert(
                            title: String(localized: "Can’t Use This Shortcut"),
                            message: String(localized: "This key can’t be used as the shortcut key.")
                        )
                    }
                )
                .fixedSize()
                if store.edgeToggleShortcut != nil {
                    Button("Reset to Default") { applyShortcut(nil) }
                }
            }
        }
    }

    /// 全局反转鼠标滚轮。作用于整个系统而不只是任务条，所以放「通用」。
    /// 说明必须写清「只改写方向值、不记录不发送」——这是全项目唯一改写别人输入事件的功能。
    @ViewBuilder
    private var scrollReverserRow: some View {
        settingRow(note: String(localized: "Flips mouse-wheel scrolling system-wide, like Scroll Reverser. Trackpads and Magic Mouse are not affected. Tungsten Edge only inverts the direction values of scroll-wheel events; nothing is recorded or sent anywhere. If Scroll Reverser or Mos is also running, the two cancel out — keep only one.")) {
            Toggle(
                "Reverse mouse scroll direction",
                isOn: binding(get: { store.scrollReverserEnabled }, set: store.setScrollReverserEnabled)
            )
        }
    }

    private func applyShortcut(_ stored: StoredHotKeyShortcut?) {
        if case .failure(let error) = coordinator.applyEdgeToggleShortcut(stored) {
            presentedAlert = SettingsAlert(
                hotKeyError: error,
                attemptedGlyphs: stored?.glyphs ?? GlobalHotKeyShortcut.edgeAutoHideMode.displayGlyphs
            )
        }
    }

    /// 授权区块。离线验证：粘一条授权码进去，本地用内嵌公钥验签名，**不联网、不绑设备**
    ///（产品决策 `Docs/27`，格式契约 `Docs/31-licensing.md`）。
    ///
    /// ⚠️ 激活成功后输入框整行消失，区块高度会变。`SettingsWindowController` 只在 `present()`
    /// 和几个 `@Published` 的订阅里重新量高度，所以那边给 `licenseStore.$state` 加了一条
    /// `.sink`——删掉它的话，激活之后窗口不会收缩，只会变成可滚动。
    ///
    /// ⚠️ 失败提示走 `SettingsAlert`，不要改成在区块里就地长出一行红字（同上，高度不会跟着变）。
    @ViewBuilder
    private var licenseRow: some View {
        switch licenseStore.state {
        case .activated(let payload):
            Text(
                String(
                    format: String(localized: "Activated · %@ · %@"),
                    payload.kind.displayTitle,
                    payload.email
                )
            )
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        case .unactivated:
            VStack(alignment: .leading, spacing: 8) {
                Text("Not activated")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    TextField("Paste your license key", text: $licenseKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { activateLicense() }
                    Button("Activate") { activateLicense() }
                        .disabled(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Founding users: your license key is in the email we sent you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func activateLicense() {
        switch licenseStore.activate(code: licenseKeyInput) {
        case .success:
            licenseKeyInput = ""
        case .failure:
            // 八种错误对用户是同一件事：这串东西不能用。分门别类地解释只会让人以为
            // 换个写法就能过——真正的行动永远是「把邮件里那串完整复制一遍」。
            presentedAlert = SettingsAlert(
                title: String(localized: "Couldn’t Activate"),
                message: String(localized: "This license key isn’t valid. Copy the whole key from your email and paste it again.")
            )
        }
    }

    @ViewBuilder
    private var aboutRow: some View {
        HStack(spacing: 12) {
            if let versionTitle = coordinator.versionTitle {
                Text(versionTitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Sparkle 自带结果界面（有新版 / 已是最新 / 查不到），所以这里不再接
            // `SettingsAlert`——原来那条「去官网手动下载」的提示随之删掉了。
            Button("Check for Updates…") {
                coordinator.checkForUpdates()
            }
            .disabled(!coordinator.canCheckForUpdates)
        }

        // 自动检查默认是开的（`SUEnableAutomaticChecks`）。**必须给关的入口**：
        // 一个用户关不掉的后台定期联网检查，比多一个勾选项糟糕得多。
        // 真值在 Sparkle 那边，这里不做镜像。
        Toggle(
            "Check for updates automatically",
            isOn: Binding(
                get: { coordinator.automaticallyChecksForUpdates },
                set: { coordinator.automaticallyChecksForUpdates = $0 }
            )
        )
    }

    /// 「原始用户，永久免费」的留邮箱入口。
    ///
    /// ⚠️ 标题和正文与官网 tungstenedge.app 的订阅区**逐字同源**（owner 逐句敲定的公开承诺），
    /// 不要在这里"改得更适合 App"——两处说法一旦分叉，将来兑现承诺时就会有人拿着不同的
    /// 版本来对质。
    ///
    /// ⚠️ 结果一律走 `SettingsAlert`，**不要**改成在区块里就地长出成功/失败文案：
    /// `SettingsWindowController.resizeToFitKeepingTopEdge()` 只在 `present()` 和
    /// `launchAtLoginState` 变化时重新量高度，就地加一行不会让窗口跟着变高，只会变成可滚动。
    @ViewBuilder
    private var subscriptionRow: some View {
        Divider()
            .padding(.vertical, 2)

        if store.hasSubscribed {
            // 已经留过的人不该被同一段话反复看见。这只是本机的显示状态，
            // 不是「是否原始用户」的凭据。
            Text("You’re subscribed. When licensing arrives, it will be sent straight to your inbox.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Founding Users · Free Forever")
                    .font(.callout.weight(.medium))
                Text("Leave your email address and your license will be sent directly to you. It survives switching devices or reinstalling macOS.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                let presentation = coordinator.subscriptionState.presentation
                HStack(spacing: 10) {
                    TextField("you@example.com", text: $subscriptionEmail)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!presentation.isEnabled)
                        .onSubmit { submitSubscription() }
                    Button(presentation.title) { submitSubscription() }
                        .disabled(!presentation.isEnabled || subscriptionEmail.isEmpty)
                }

                // ⚠️ 上报首装日期这件事必须写在界面上。一个常驻工具偷偷上报安装日期
                // 被人发现，损失远大于这份名单的价值。
                Text("Only your email address and first-launch date are sent, to confirm you as a founding user. No marketing email.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// GitHub 的 Star 请求。**常驻**，和有没有订阅过无关——所以它是 `subscriptionRow` 的
    /// 同级兄弟，不塞进那个 if/else 里。
    ///
    /// ⚠️ 调子沿用官网 tungstenedge.app 订阅区那段（`index.html` 里的 `.sub-star`）已经定死的
    /// 三条规矩，别在这里重新发挥：
    /// 1. **常驻**，不是订阅成功之后才冒出来——用户得先在视野里见过它，回头点起来才顺理成章。
    /// 2. **比订阅正文更淡**。它是"顺手帮个忙"，不能压过留邮箱的真实理由。官网用
    ///    `opacity .5 / font-weight 300 / 12.5px`；这里对应 `.caption`，而订阅正文是 `.callout`。
    /// 3. **只说这一次**。订阅结果的 `SettingsAlert` 里不要再提 Star——它一直在视野里，
    ///    重复只会变吵，还会跟"去邮箱点确认"抢注意力（那一步不点就进不了名单，是承重的）。
    ///
    /// ⚠️ 链接用 `Button` 而不是 SwiftUI 的 `Link`：`Scripts/check_localization.py` 的正则
    /// 不扫 `Link(...)`，改成 `Link` 会让这条文案悄悄绕过本地化检查、在中文系统上露出英文。
    ///
    /// ⚠️ 整句是**一个**本地化条目，不要拆成「前半句 + GitHub 按钮 + 后半句」：
    /// 中英文里 GitHub 出现的位置不一样，拆开就没法翻译了。
    private var githubStarRow: some View {
        Button {
            NSWorkspace.shared.open(SettingsWindowView.repositoryURL)
        } label: {
            Text("Star Tungsten Edge on GitHub — a free way to help it get better.")
        }
        .buttonStyle(.link)
        .font(.caption)
    }

    private func submitSubscription() {
        // 在飞守卫在共享层，和检查更新同一套路。
        guard coordinator.beginSubscription() else { return }
        let email = subscriptionEmail
        Task {
            let content = await coordinator.performSubscription(email: email)
            coordinator.finishSubscription()
            if content.didSubscribe { subscriptionEmail = "" }
            presentedAlert = SettingsAlert(content)
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 开关 + 一行灰色说明。说明是给「不知道这个开关在干嘛」的人看的，
    /// 菜单里塞不下，设置窗口有的是地方。
    private func settingRow<Content: View>(
        note: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            content()
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding<Value>(
        get: @escaping () -> Value,
        set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: get, set: set)
    }
}

private struct SettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let openButtonTitle: String?
    let openURL: URL?

    init(title: String, message: String, openButtonTitle: String? = nil, openURL: URL? = nil) {
        self.title = title
        self.message = message
        self.openButtonTitle = openButtonTitle
        self.openURL = openURL
    }

    init(_ content: SubscriptionAlertContent) {
        self.init(title: content.title, message: content.message)
    }

    /// 改键失败 → 一句能行动的人话。拒绝理由逐条给（每条的下一步动作不同）；
    /// 注册失败只有一种真实成因（组合被别的应用独占注册）。
    init(hotKeyError: HotKeyChangeError, attemptedGlyphs: String) {
        switch hotKeyError {
        case .rejected(.missingPrimaryModifier):
            self.init(
                title: String(localized: "Can’t Use This Shortcut"),
                message: String(localized: "Use at least one of Command, Control or Option.")
            )
        case .rejected(.unreliableModifiers):
            self.init(
                title: String(localized: "Can’t Use This Shortcut"),
                message: String(localized: "Option alone or Option-Shift is unreliable on macOS 15.")
            )
        case .rejected(.reservedBySystem):
            self.init(
                title: String(localized: "Can’t Use This Shortcut"),
                message: String(localized: "This combination belongs to macOS (⌥⌘D shows/hides the Dock; Control-Option is VoiceOver’s).")
            )
        case .rejected(.forbiddenKey):
            self.init(
                title: String(localized: "Can’t Use This Shortcut"),
                message: String(localized: "Escape and Delete can’t be the key.")
            )
        case .registrationFailed:
            self.init(
                title: String(localized: "Couldn’t Register the Shortcut"),
                message: String(
                    format: String(localized: "%@ is already taken by another app. The previous shortcut stays active."),
                    attemptedGlyphs
                )
            )
        }
    }
}

extension LicenseKind {
    /// 授权种类给用户看的名字。`LicenseVerifier` 那边是纯逻辑、不带文案，所以放在这里。
    /// 用词照 `Docs/30-i18n-glossary.md`：founding = 原始用户 / Founding User。
    var displayTitle: String {
        switch self {
        case .founding: return String(localized: "Founding User")
        case .paid: return String(localized: "Paid")
        }
    }
}
