import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsWindowView: View {
    static let contentWidth: CGFloat = 560

    /// 公开仓库主页。**只给「求 Star」用**——用户可见的「去下载」永远指向官网
    /// （2026-08-13 起 GitHub release 页不再附安装包，指过去是个空页面），
    /// 别顺手把下载入口也改到 GitHub 来。
    static let repositoryURL = URL(string: "https://github.com/moonbai-studio/tungsten-edge")!

    @ObservedObject var store: AppSettingsStore
    @ObservedObject var coordinator: SettingsCoordinator
    @ObservedObject var licenseStore: LicenseStore
    @ObservedObject var tabState: SettingsTabState

    var body: some View {
        // ScrollView 保留作小屏兜底：每页正常都短于一屏，量高把窗口撑到内容高度，滚动不出现。
        // **指示器必须关**：滚动条样式为「自动」且接了鼠标时是占位式的，出现时吃掉约 15pt 可视宽，
        // 切页动画那 0.2 秒内容溢出 → 滚动条在位 → 整页水平平移一下。内层也不许写死宽度（见下）。
        ScrollView(.vertical, showsIndicators: false) {
            SettingsWindowContent(
                store: store,
                coordinator: coordinator,
                licenseStore: licenseStore,
                tabState: tabState
            )
        }
        .frame(width: Self.contentWidth)
    }
}

struct SettingsWindowContent: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject var coordinator: SettingsCoordinator
    @ObservedObject var licenseStore: LicenseStore
    @ObservedObject var tabState: SettingsTabState

    @State private var presentedAlert: SettingsAlert?
    @State private var subscriptionEmail = ""
    @State private var licenseKeyInput = ""
    @State private var feedbackMessage = ""
    @State private var feedbackContact = ""
    // 反馈类型也是草稿：和 message/contact 一样必须留在根视图，下放进页级子视图 = 切页被清空。
    @State private var feedbackCategory: FeedbackCategory = .bug
    // 附件列表同理（2026-08-24）：切页回来必须还在，否则用户以为附件掉了会重加一遍。
    @State private var feedbackAttachments: [FeedbackAttachment] = []

    var body: some View {
        Group {
            switch tabState.selected {
            case .general: generalPane
            case .taskbar: taskbarPane
            case .advanced: advancedPane
            case .license: licensePane
            case .feedback: feedbackPane
            case .about: aboutPane
            }
        }
        .padding(28)
        // **不许写死宽度**：外面套着 ScrollView，刚性宽度在可视区变窄时会被居中 = 整页平移。
        // 弹性宽度下左边缘恒在 padding 处，最多重排换行。测高探针给的仍是 contentWidth 的提案。
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert(item: $presentedAlert) { alert in
            guard let actionTitle = alert.actionTitle, let action = alert.action else {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text(actionTitle), action: action),
                secondaryButton: .cancel(Text("Later"))
            )
        }
    }

    // 分区标题行随分页取消（窗口标题承担）。页体全部是**本根视图**的计算属性——
    // 草稿 @State（presentedAlert / 订阅邮箱 / 授权码 / 反馈正文与联系方式）必须留在根上，
    // 下放进页级子视图 = 切页即清空（settings.md 有对应规则）。
    @ViewBuilder
    private var generalPane: some View {
        settingsPane {
            languageRow
            hotKeyRow
            scrollReverserRow
        }
    }

    @ViewBuilder
    private var taskbarPane: some View {
        settingsPane {
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
    }

    // 「高级」= 需要额外能力、默认就对、基本不用碰的开关。单独一页不是为了藏，
    // 而是让常用页只留日常会调的东西；真想拒绝这个能力的人找得到（owner 2026-08-09，
    // 2026-08-24 分页时 owner 确认保留「高级」这一页）。
    @ViewBuilder
    private var advancedPane: some View {
        settingsPane {
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
    }

    @ViewBuilder
    private var licensePane: some View {
        settingsPane {
            licenseRow
        }
    }

    @ViewBuilder
    private var feedbackPane: some View {
        settingsPane {
            feedbackRow
        }
    }

    @ViewBuilder
    private var aboutPane: some View {
        settingsPane {
            aboutRow
            subscriptionRow
            githubStarRow
        }
    }

    // 登录时启动 2026-08-24 当天两度搬家：随去重进过设置窗口，owner 复议后定为
    // **只在状态栏菜单（第一项）**。这里不再放它，也不再需要 didBecomeActive 刷新。

    /// 界面语言（2026-08-24，反转 8-17「不做语言开关」，见 `Docs/27`）。写**应用自己域**的
    /// `AppleLanguages`（与 macOS 13+ 逐 App 语言同一个键），「跟随系统」= 删键；重启生效。
    /// 读现状必须走 `CFPreferencesCopyAppValue`——`array(forKey:)` 会继承全局域，
    /// 分不清「跟随系统」和「显式设置」（`AppLanguageOption` 注释是权威）。
    @ViewBuilder
    private var languageRow: some View {
        settingRow(note: String(localized: "The language change takes effect after Tungsten Edge restarts.")) {
            Picker(
                String(localized: "Language"),
                selection: Binding(
                    get: { Self.currentLanguageOption() },
                    set: { applyLanguage($0) }
                )
            ) {
                ForEach(AppLanguageOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 280, alignment: .leading)
        }
    }

    private static func currentLanguageOption() -> AppLanguageOption {
        let bundleID = (Bundle.main.bundleIdentifier ?? "") as CFString
        let value = CFPreferencesCopyAppValue("AppleLanguages" as CFString, bundleID) as? [String]
        return AppLanguageOption.current(appDomainValue: value)
    }

    private func applyLanguage(_ option: AppLanguageOption) {
        guard option != Self.currentLanguageOption() else { return }
        if let value = option.appleLanguagesValue {
            UserDefaults.standard.set(value, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        presentedAlert = SettingsAlert(
            title: String(localized: "Language"),
            message: String(localized: "The language change takes effect after Tungsten Edge restarts."),
            actionTitle: String(localized: "Restart Tungsten Edge"),
            action: { Self.relaunch() }
        )
    }

    /// 分离一个「睡半秒再 open」的壳进程后自退。新实例启动时旧的已退干净，
    /// `terminateOtherInstances()` 不会反杀谁。环境无需再清——本进程入口处
    /// `ProcessEnvironmentScrub.apply()` 已经清过，子进程继承的就是干净环境。
    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        try? process.run()
        NSApp.terminate(nil)
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
            // ⚠️ 这一页说出口的每样东西都必须和「授权码到底发没发」对得上。2026-08-25 之前
            // 它既说「授权码在我们发给你的那封邮件里」，又摆着一个「粘贴授权码」输入框，
            // 而当时**一条授权码都没签发过**——文案和控件在说同一句假话，反馈里因此收到
            // 「邮箱并没有收到激活码」。发放没开始时这里只说明现状：没有状态行（没东西可
            // 激活时「未激活」只会让人以为该去激活点什么），没有输入框，没有按钮。
            //
            // 恢复方式：`LicenseStore.isIssuingLicenses` 翻成 true。**用 if 而不是注释掉，
            // 是为了让两个分支都参与编译**——注释掉的代码没人记得恢复，也会让
            // `activateLicense()` 变成无引用。
            VStack(alignment: .leading, spacing: 8) {
                if LicenseStore.isIssuingLicenses {
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
                }
                // 发放开始后它退回配角（输入框才是主角），所以字号跟着开关走。
                Text("Licensing opens with version 1.0. Tungsten Edge is completely free until then, and founding users who have confirmed their email will receive a permanent free license key.")
                    .font(LicenseStore.isIssuingLicenses ? .caption : .callout)
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

    /// 应用内反馈表单（2026-08-24，同日拎成独立标签页）：类型三选一 + 随类型变的引导
    /// 文字 + 正文 + 选填联系方式 → 官网 `/api/feedback` → D1，owner 在本机控制台看。
    /// 为什么不是 GitHub / mailto：国内用户打不开 GitHub，mailto 依赖装好的邮件客户端。
    ///
    /// ⚠️ **所有高度固定**（TextEditor 定高 140pt；placeholder 是 overlay，不占布局；
    /// 附件区定高 44pt 且**始终渲染**，加到 3 个也不换行；发送后清空不改布局），
    /// 结果一律走 `SettingsAlert`——窗口只在 `present()`、license sink 和切页时量高度，
    /// 就地长出状态行或让附件把 pane 顶高，都只会变成可滚动。
    /// ⚠️ 披露行必须与实际发送的内容一致（六项：正文 / 联系方式 / 版本 / macOS / 语言 / 附件）；
    /// 类型并入 message（`FeedbackComposition` 是组装唯一入口），不是独立字段。
    @ViewBuilder
    private var feedbackRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ran into a problem or have an idea? Write to us here.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text("Type")
                    .font(.callout)
                Picker("Type", selection: $feedbackCategory) {
                    ForEach(FeedbackCategory.allCases, id: \.self) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
            }

            TextEditor(text: $feedbackMessage)
                .font(.callout)
                .frame(height: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if feedbackMessage.isEmpty {
                        Text(feedbackCategory.placeholder)
                            .font(.callout)
                            .foregroundStyle(Color(nsColor: .placeholderTextColor))
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                    }
                }

            let presentation = coordinator.feedbackState.presentation
            feedbackAttachmentRow(isEnabled: presentation.isEnabled)

            HStack(spacing: 10) {
                TextField(String(localized: "Email or WeChat ID (optional)"), text: $feedbackContact)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!presentation.isEnabled)
                Button(presentation.title) { submitFeedback() }
                    .disabled(
                        !presentation.isEnabled
                            || feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }

            Text("Only your message, the contact you enter, the app version, your macOS version, the interface language and the attachments you add (kept for at most 90 days) are sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 附件区：一行，**定高 44pt，始终渲染**（一个都没加时也占着这行）。
    /// 高度绝不能随附件增减变化——设置窗口只在 present / 切页 / license sink 三处量高度，
    /// 就地长高只会让内容溢出成可滚动（`.claude/rules/settings.md` 是权威）。
    /// 因此：胶囊限宽、文件名中间截断、整行 `.frame(height:)` + `.clipped()` 兜底。
    @ViewBuilder
    private func feedbackAttachmentRow(isEnabled: Bool) -> some View {
        HStack(spacing: 8) {
            Button(String(localized: "Add Screenshot or Recording…")) { addFeedbackAttachments() }
                .disabled(!isEnabled || feedbackAttachments.count >= FeedbackAttachmentCheck.maximumCount)
            ForEach(feedbackAttachments) { attachment in
                feedbackAttachmentChip(attachment, isEnabled: isEnabled)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 44)
        .clipped()
    }

    private func feedbackAttachmentChip(_ attachment: FeedbackAttachment, isEnabled: Bool) -> some View {
        HStack(spacing: 4) {
            Text(attachment.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(attachment.sizeLabel)
                .foregroundStyle(.secondary)
            Button {
                feedbackAttachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .help(String(localized: "Remove Attachment"))
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: 116)
        .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor)))
    }

    /// 选文件。可多选，逐个按同一套纯校验放行；**第一个被拒的就当场弹窗并停下**——
    /// 已经加进去的保留，用户看得见自己还剩几个名额。校验全在本地，40MB 传上去
    /// 再被服务端 400 拒回来，那几分钟是白等的。
    private func addFeedbackAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.feedbackAttachmentContentTypes
        panel.prompt = String(localized: "Attach")
        panel.message = String(localized: "Choose screenshots or screen recordings to send with your feedback.")
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            let name = url.lastPathComponent
            let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if let rejection = FeedbackAttachmentCheck.validate(
                adding: name, byteCount: byteCount, to: feedbackAttachments
            ) {
                presentedAlert = SettingsAlert(FeedbackAlertContent(attachmentRejection: rejection))
                return
            }
            guard let mimeType = FeedbackAttachmentCheck.mimeType(forFileName: name) else { return }
            feedbackAttachments.append(FeedbackAttachment(
                url: url, name: name, byteCount: byteCount, mimeType: mimeType
            ))
        }
    }

    /// 与 `FeedbackAttachmentCheck` 的扩展名白名单一一对应。多放一种，服务端会 400。
    private static let feedbackAttachmentContentTypes: [UTType] = [
        .png, .jpeg, .gif, .heic, .quickTimeMovie, .mpeg4Movie
    ]

    private func submitFeedback() {
        // 先组装再上锁：空正文直接返回，不占 submitting 状态（按钮 disabled 已挡，这里兜底）。
        guard let composed = FeedbackComposition.compose(
            category: feedbackCategory, message: feedbackMessage
        ) else { return }
        guard coordinator.beginFeedback() else { return }
        let contact = feedbackContact
        let attachments = feedbackAttachments
        Task {
            let content = await coordinator.performFeedback(
                message: composed, contact: contact, attachments: attachments
            )
            coordinator.finishFeedback()
            // 失败时草稿**全保留**（含附件列表）：40MB 重选一遍是很实在的惩罚。
            if content.didSend {
                feedbackMessage = ""
                feedbackContact = ""
                feedbackCategory = .bug
                feedbackAttachments = []
            }
            presentedAlert = SettingsAlert(content)
        }
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

    /// 一页的行容器。分区标题随 2026-08-24 分页取消（窗口标题承担），只剩统一行距。
    private func settingsPane<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
    /// 可选的第二个按钮（如语言切换的「立即重启」）。为 nil 时只有「好」。
    let actionTitle: String?
    let action: (() -> Void)?

    init(title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    init(_ content: SubscriptionAlertContent) {
        self.init(title: content.title, message: content.message)
    }

    init(_ content: FeedbackAlertContent) {
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
