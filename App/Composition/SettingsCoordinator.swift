import Combine
import Foundation

struct NativeDockApplyOutcome {
    let resolvedDelay: Double
    let error: Error?
}

/// 状态栏菜单与设置窗口**共用**的动作层。
///
/// 职责刻意收窄到「会写到本 App 之外」的三件事：登录项、系统 Dock、检查更新。
/// 钨极自己的本地开关（中转站 / 悬停 / 避让 / 任务条大小 / 唤醒延迟）不经这里——
/// 它们是即时生效的本地值，两套界面直接观察同一个 `AppSettingsStore` 就不会脱节。
@MainActor
final class SettingsCoordinator: ObservableObject {
    /// 最近一次系统读取或本 App 成功写入的结果。系统 I/O 在服务的专用队列执行，
    /// 菜单与设置窗口先显示这份缓存，再异步刷新。
    @Published private(set) var launchAtLoginState: LaunchAtLoginState
    /// 在飞守卫放在共享层：两套界面各有一个「检查更新」入口，
    /// 各自守卫的话同时点两下会发两次请求。
    @Published private(set) var updateCheckState = UpdateCheckMenuState()
    /// 同理：订阅按钮连点两下不能发两次请求。
    @Published private(set) var subscriptionState = SubscriptionSubmitState()

    private let store: AppSettingsStore
    private let launchAtLoginService: LaunchAtLoginServicing
    private let nativeDockPreferencesService: NativeDockPreferencesServicing
    private let updateChecker: UpdateChecking
    private let subscriptionSubmitter: SubscriptionSubmitting
    private var launchRefreshGeneration: UInt64 = 0
    private var nativeDockRefreshGeneration: UInt64 = 0
    private var nativeDockWriteInFlight = false

    init(
        store: AppSettingsStore,
        launchAtLoginService: LaunchAtLoginServicing,
        nativeDockPreferencesService: NativeDockPreferencesServicing,
        updateChecker: UpdateChecking,
        subscriptionSubmitter: SubscriptionSubmitting
    ) {
        self.store = store
        self.launchAtLoginService = launchAtLoginService
        self.nativeDockPreferencesService = nativeDockPreferencesService
        self.updateChecker = updateChecker
        self.subscriptionSubmitter = subscriptionSubmitter
        // **镜像只作首帧种子，不是真值来源。** `SMAppService.mainApp.status` 是 XPC，
        // 放在 init 里同步读会把开销带进每一次界面构造；而每个展示入口（菜单 `menuWillOpen`、
        // 设置窗口 `present()`、`applicationDidBecomeActive`）都会立刻异步刷新，
        // 所以这里读本地镜像只是让第一帧有东西显示。
        //
        // 代价说清楚：用户在系统设置里改过登录项、而本 App 那时没运行的话，首帧勾选可能是错的
        // （`.requiresApproval` 也会先显示成 `.on`），一个刷新周期内自愈。**绝不能**因此
        // 把镜像当成长期真值——`launchAtLoginState` 的写入口只有 `refreshLaunchAtLoginState`
        // 与写成功后的乐观更新两处。
        if #available(macOS 13.0, *) {
            launchAtLoginState = store.launchAtLogin ? .on : .off
        } else {
            launchAtLoginState = .unsupported
        }
    }

    // MARK: 登录项

    /// 返回 false 表示结果已经过期或任务被取消，调用方不得用它刷新在屏 UI。
    @discardableResult
    func refreshLaunchAtLoginState() async -> Bool {
        launchRefreshGeneration &+= 1
        let generation = launchRefreshGeneration
        let next = await launchAtLoginService.currentState()
        guard !Task.isCancelled, generation == launchRefreshGeneration else { return false }
        if launchAtLoginState != next { launchAtLoginState = next }
        return true
    }

    /// 只有**写成功**才更新本地镜像：镜像存在的意义是「我们以为的状态」，
    /// 写失败时系统那边没变，镜像跟着变会让下次展示说谎。
    func setLaunchAtLogin(_ enabled: Bool) -> Result<Void, Error> {
        launchRefreshGeneration &+= 1
        do {
            try launchAtLoginService.setEnabled(enabled)
            store.setLaunchAtLogin(enabled)
            let optimistic: LaunchAtLoginState = enabled ? .on : .off
            if launchAtLoginState != optimistic { launchAtLoginState = optimistic }
            refreshLaunchAtLoginStateSoon()
            return .success(())
        } catch {
            refreshLaunchAtLoginStateSoon()
            return .failure(error)
        }
    }

    private func refreshLaunchAtLoginStateSoon() {
        Task { @MainActor [weak self] in
            _ = await self?.refreshLaunchAtLoginState()
        }
    }

    func openLoginItemsSettings() {
        launchAtLoginService.openSystemSettings()
    }

    // MARK: 系统 Dock

    /// 只改本地镜像让 UI 对齐系统真值，**绝不反向应用**——展示一次设置界面
    /// 不该招来一次 `killall Dock`。写入期间不发起竞争读取；迟到的旧读取由代次丢弃。
    /// 返回 false 表示本次结果未被接受，调用方不得据此刷新在屏 UI。
    @discardableResult
    func reconcileNativeDockMirror() async -> Bool {
        guard !nativeDockWriteInFlight else { return false }
        nativeDockRefreshGeneration &+= 1
        let generation = nativeDockRefreshGeneration
        let state = await nativeDockPreferencesService.currentAutohideState()
        guard !Task.isCancelled,
              !nativeDockWriteInFlight,
              generation == nativeDockRefreshGeneration else { return false }
        _ = reconcileNativeDockMirror(using: state)
        return true
    }

    @discardableResult
    private func reconcileNativeDockMirror(using state: NativeDockAutohideState?) -> Double {
        guard let state else {
            // 读不到系统真值（沙箱等）时保持镜像不动，调用方按当前镜像继续。
            return store.nativeDockAutoHideDelay
        }
        if let target = AutoHideToggleMenuModel.reconciledStoreDelay(
            systemEnabled: state.enabled,
            systemDelay: state.delay,
            currentStoreDelay: store.nativeDockAutoHideDelay
        ) {
            store.setNativeDockAutoHideDelay(target)
        }
        return store.nativeDockAutoHideDelay
    }

    /// 系统 Dock 的**唯一**写入路径。
    ///
    /// `previous` 不由界面传进来：草稿摊在屏幕上的这段时间里，用户随时可能用 ⌥⌘D 或
    /// 系统设置改掉真值，界面手里那个起点早就过期了。所以写之前先重读一次系统真值。
    ///
    /// defaults + killall 是多步非事务序列，写完一律重读系统真值再决定镜像落什么
    /// （四象限见 `AutoHideToggleMenuModel.resolvedStoreDelay`）。这里**不弹窗**：
    /// 弹窗归调用方，两套界面的弹法不一样（菜单用 NSAlert，设置窗口用附着式 alert）。
    func applyNativeDock(target: Double) async -> NativeDockApplyOutcome {
        guard nativeDockPreferencesService.isAvailable else {
            return NativeDockApplyOutcome(
                resolvedDelay: store.nativeDockAutoHideDelay,
                error: NativeDockPreferencesError.sandboxed
            )
        }

        nativeDockWriteInFlight = true
        nativeDockRefreshGeneration &+= 1
        defer { nativeDockWriteInFlight = false }

        let previousState = await nativeDockPreferencesService.currentAutohideState()
        let previous = reconcileNativeDockMirror(using: previousState)
        var writeError: Error?
        do {
            try nativeDockPreferencesService.apply(delay: target)
        } catch {
            writeError = error
        }

        let readback = await nativeDockPreferencesService.currentAutohideState()
        let resolved = AutoHideToggleMenuModel.resolvedStoreDelay(
            writeSucceeded: writeError == nil,
            systemState: readback,
            target: target,
            previous: previous
        )
        store.setNativeDockAutoHideDelay(resolved)
        return NativeDockApplyOutcome(resolvedDelay: resolved, error: writeError)
    }

    func openNativeDockSettings() -> Bool {
        nativeDockPreferencesService.openSystemSettings()
    }

    // MARK: 检查更新

    /// 版本行同时给菜单和设置窗口用。发布后主线不 bump 版本号，光看数字分不出开发构建和
    /// 用户装的包，所以把来源一并显示出来（判定在纯 `BuildProvenance` 里，有单测）。
    var versionTitle: String? {
        let info = Bundle.main.infoDictionary
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return BuildProvenance.versionTitle(
            version: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String,
            isDebugBuild: isDebugBuild,
            bundlePath: Bundle.main.bundleURL.path
        )
    }

    /// 返回 false = 已经有一次检查在飞，本次忽略。
    func beginUpdateCheck() -> Bool {
        updateCheckState.begin()
    }

    func finishUpdateCheck() {
        updateCheckState.finish()
    }

    func performUpdateCheck() async -> UpdateCheckAlertContent {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        do {
            let outcome = try await updateChecker.check(currentVersion: currentVersion)
            return UpdateCheckAlertContent(outcome: outcome)
        } catch {
            return .failure
        }
    }

    // MARK: 邮箱订阅

    /// 返回 false = 已经有一次提交在飞，本次忽略。
    func beginSubscription() -> Bool {
        subscriptionState.begin()
    }

    func finishSubscription() {
        subscriptionState.finish()
    }

    /// 把 throws 吞成「一定有文案」，界面层不处理 error——和 `performUpdateCheck` 同一约定。
    ///
    /// 首装日期从 `InstallationRecord` 现取：它是「原始用户」的主凭据，随邮箱一起送上去，
    /// 将来兑现承诺时才能按安装时间筛人，而不是只能看订阅时间。
    /// ⚠️ 上报这个日期的事**必须**写在设置界面上，不能悄悄发。
    func performSubscription(email: String) async -> SubscriptionAlertContent {
        do {
            let outcome = try await subscriptionSubmitter.submit(
                email: email,
                firstLaunchDate: InstallationRecord.firstLaunchDate()
            )
            let content = SubscriptionAlertContent(outcome: outcome)
            if content.didSubscribe {
                store.setHasSubscribed(true)
            }
            return content
        } catch SubscriptionError.invalidEmail {
            return .invalidEmail
        } catch {
            return .failure
        }
    }
}
