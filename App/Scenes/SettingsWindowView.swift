import AppKit
import SwiftUI

struct SettingsWindowView: View {
    static let contentWidth: CGFloat = 560

    @ObservedObject var store: AppSettingsStore
    @ObservedObject var coordinator: SettingsCoordinator

    var body: some View {
        ScrollView(.vertical) {
            SettingsWindowContent(store: store, coordinator: coordinator)
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

    @State private var presentedAlert: SettingsAlert?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection("通用") {
                launchAtLoginRow
            }

            Divider()

            settingsSection("任务条") {
                settingRow(note: "任务条上多一个临时存放文件的格子。拖进去的文件不会被移动或复制，只是记住位置。") {
                    Toggle("显示中转站", isOn: binding(get: { store.showShelf }, set: store.setShowShelf))
                }

                settingRow(note: "关闭后，鼠标划过任务条不再有放大和名称提示。") {
                    Toggle(
                        "鼠标悬停显示应用名",
                        isOn: binding(get: { store.hoverStyle.isExpressive }) {
                            store.setHoverStyle($0 ? .standard : .quiet)
                        }
                    )
                }

                settingRow(note: "把铺满屏幕的窗口底边抬到任务条上方。这会改动其他应用的窗口尺寸，所以默认关闭。") {
                    Toggle(
                        "最大化窗口避开任务条",
                        isOn: binding(get: { store.windowLiftEnabled }, set: store.setWindowLiftEnabled)
                    )
                }

                settingRow(note: "会监听全局鼠标点击和按键，只识别窗口绿灯与 Control-Command-F，不记录输入内容。") {
                    Toggle(
                        "进入全屏时避免闪烁",
                        isOn: binding(
                            get: { store.fullscreenIntentEnabled },
                            set: store.setFullscreenIntentEnabled
                        )
                    )
                }

                Picker("任务条大小", selection: binding(get: { store.dockSize }, set: store.setDockSize)) {
                    ForEach(DockSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                // 唤醒时间是连续档位、会随手调，留在菜单里；这里只指路，别让人在设置窗口里
                // 找自动隐藏找到死胡同（owner 2026-08-03 的分工：滑块类进菜单，开关类进这里）。
                pointerNote("任务条的自动隐藏和唤醒时间在**菜单栏的钨极图标**里调——那条滑块拖着就生效，方便一边拖一边看。")
            }

            Divider()

            settingsSection("系统 Dock") {
                pointerNote("这一组说的是 macOS 自带的程序坞，不是钨极。它的自动隐藏和唤醒时间同样在**菜单栏的钨极图标**里调（改动要点「应用」才生效，生效时系统 Dock 会重启一下）。")

                Button {
                    if !coordinator.openNativeDockSettings() {
                        presentedAlert = SettingsAlert(
                            title: "无法打开系统 Dock 设置",
                            message: "请从系统设置进入「桌面与程序坞」（macOS 12 为「程序坞与菜单栏」）。"
                        )
                    }
                } label: {
                    Label("打开系统 Dock 设置…", systemImage: "arrow.up.forward.app")
                }
            }

            Divider()

            settingsSection("关于") {
                aboutRow
            }
        }
        .padding(28)
        .frame(width: SettingsWindowView.contentWidth, alignment: .leading)
        .alert(item: $presentedAlert) { alert in
            guard let openButtonTitle = alert.openButtonTitle, let openURL = alert.openURL else {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("好"))
                )
            }
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text(openButtonTitle)) { NSWorkspace.shared.open(openURL) },
                secondaryButton: .cancel(Text("稍后"))
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
                            title: "登录时启动设置失败",
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
                Label("打开登录项设置…", systemImage: "arrow.up.forward.app")
            }
        }
    }

    @ViewBuilder
    private var aboutRow: some View {
        let updatePresentation = coordinator.updateCheckState.presentation
        HStack(spacing: 12) {
            if let versionTitle = coordinator.versionTitle {
                Text(versionTitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(updatePresentation.title) {
                // 在飞守卫在共享层：菜单里那条「检查更新」用的是同一个。
                guard coordinator.beginUpdateCheck() else { return }
                Task {
                    let content = await coordinator.performUpdateCheck()
                    coordinator.finishUpdateCheck()
                    presentedAlert = SettingsAlert(content)
                }
            }
            .disabled(!updatePresentation.isEnabled)
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

    /// 指路行：这条设置不在本窗口里，告诉用户去哪调。**必须写清去处**——
    /// 少了它，用户在设置窗口里找自动隐藏就是撞死胡同，而"找不到设置"正是这轮的起因。
    private func pointerNote(_ markdown: String) -> some View {
        Text(.init(markdown))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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

    init(_ content: UpdateCheckAlertContent) {
        self.init(
            title: content.title,
            message: content.message,
            openButtonTitle: content.openButtonTitle,
            openURL: content.openURL
        )
    }
}
