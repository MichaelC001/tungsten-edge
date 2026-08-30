import ApplicationServices
import CoreGraphics

enum PanelVisibilityReason: Hashable {
    case fullscreen
    case fullscreenTransitionPending
    case edgeAutoHide
}

enum FullscreenSpaceHoldDisposition: Equatable {
    case apply
    case hold
    case stale
}

enum FullscreenSpaceHoldDecision {
    static let postSpaceConfirmationDelay: TimeInterval = 0.12
    static let activationFallbackDelay: TimeInterval = 0.5

    static func shouldBegin(isFullscreen: Bool, hasInputIntent: Bool) -> Bool {
        isFullscreen && !hasInputIntent
    }

    static func disposition(
        isFullscreenVerdict: Bool,
        expectedGeneration: UInt64?,
        activeGeneration: UInt64?,
        isFinalWindowedConfirmation: Bool
    ) -> FullscreenSpaceHoldDisposition {
        guard let activeGeneration else {
            return expectedGeneration == nil ? .apply : .stale
        }
        guard expectedGeneration == activeGeneration else { return .stale }
        if isFullscreenVerdict || isFinalWindowedConfirmation { return .apply }
        return .hold
    }
}

// 异步 AX 全屏探测的纯判定（PanelCoordinator.detectFullscreenViaAX 调用）。
// role 门禁是硬约束：Finder 挂着一个桌面伪窗口（role=AXScrollArea，frame 恰好等于整屏），
// 恢复最小化窗口的瞬间它会成为 AXFocusedWindow —— 没有门禁就命中 frame≈整屏兜底，任务条被误隐藏。
enum FullscreenWindowClassifier {
    static let frameTolerance: CGFloat = 8

    static func isFullscreen(
        role: String?,
        isAXFullscreen: Bool,
        windowFrame: CGRect?,
        screenCGFrame: CGRect
    ) -> Bool {
        guard role == kAXWindowRole else { return false }

        if isAXFullscreen {
            guard let wf = windowFrame else { return true }
            // 归属判据（面积主体在本屏），不是宽度判据。原来的 `width > screen × 0.7` 兼任
            // 多屏护栏，但把**全屏幕拼贴（真分屏）的半宽 tile 误否**——2026-08-30 实测
            // （macOS 26.5.2，`scratch/space-probe-20260830-2106.log`）：分屏 tile 报
            // AXFullScreen=true、frame=(0,40 1278×1400)，1278 < 2560×0.7 被否，任务条
            // 因此盖在分屏内容上（0.9.10 反馈 `02525cc5`）。面积归属保住护栏的本意：
            // 同日实测另一块屏上的全屏窗口与本屏不相交，照样拦下。
            return mostlyBelongsToScreen(wf, screenCGFrame)
        }

        // Fallback: frame ≈ full screen (games / HTML5 that skip the AXFullScreen flag)
        if let wf = windowFrame {
            let t = frameTolerance
            return abs(wf.width  - screenCGFrame.width)  < t
                && abs(wf.height - screenCGFrame.height) < t
                && abs(wf.minX   - screenCGFrame.minX)   < t
                && abs(wf.minY   - screenCGFrame.minY)   < t
        }

        return false
    }

    /// 窗口面积的一半以上落在这块屏上才算「属于本屏」。纯 CGRect 数学——
    /// `FullscreenIntentMonitor.readAXState` 也调本判定，结果在事件 tap 线程上消费，
    /// 这里不允许出现 AX / AppKit / 日志（见 panels-and-screens 规则）。
    /// 与 `WindowLiftAvoidance` 里私有的同名方法是同一个面积法，刻意不共享——
    /// 避让那份冻结在自己的规则文件里，两边耦合反而让改动更危险。
    private static func mostlyBelongsToScreen(_ frame: CGRect, _ screen: CGRect) -> Bool {
        let frameArea = frame.width * frame.height
        guard frameArea > 0 else { return false }
        let overlap = frame.intersection(screen)
        guard !overlap.isNull, !overlap.isEmpty else { return false }
        return overlap.width * overlap.height >= frameArea * 0.5
    }
}

/// 「常驻所有桌面」的成员资格修复（issue #19）。
///
/// macOS 会在**一个全屏空间被销毁的那一刻，把当时处于隐藏状态的 `.canJoinAllSpaces` 窗口
/// 重新只挂到当前那个桌面上**，其余桌面从此看不到它。2026-08-28 用一个 80 行、与本项目
/// 无关的独立实验复现（`scratch/space_membership_lab2.swift`），所以这不是钨极的 bug，
/// 但受害的正是我们「进全屏 orderOut / 退全屏 orderFrontRegardless」这套让位机制。
///
/// 补不回来的做法（都实测过）：`orderFrontRegardless`、把同样的 `collectionBehavior`
/// 再赋一遍、`orderOut` + 重设 + `orderFront`。**有效的唯一形状是：换成别的值 → 让它过一轮
/// runloop → 再赋回**，而且**单次不保证成功**（3 轮实验里有 1 轮要修两次），所以必须
/// 读回验收 + 重试，不能一发了事。
enum AllSpacesMembership {
    static let maxRepairAttempts = 3
    /// 赋回之后等多久再读回验收。实测 120ms 足够 WindowServer 落定。
    static let verifyDelay: TimeInterval = 0.12

    /// 这扇窗还缺哪些普通桌面（全屏空间不算——窗口本来就不该常驻在别人的全屏空间上）。
    /// 空数组 = 健康。`desktopSpaceIDs` 少于 2 个时永远返回空：单桌面谈不上「丢桌面」。
    static func missingSpaceIDs(windowSpaceIDs: [Int], desktopSpaceIDs: [Int]) -> [Int] {
        guard desktopSpaceIDs.count > 1 else { return [] }
        let owned = Set(windowSpaceIDs)
        return desktopSpaceIDs.filter { !owned.contains($0) }.sorted()
    }

    static func shouldRetry(attempt: Int) -> Bool { attempt < maxRepairAttempts }
}

enum EdgeAutoHideInhibitor: Hashable {
    case dragging
    case drawerOpen
    case folderPopupOpen
    /// 钨极菜单（状态栏图标或任务条右键弹出的那一个）正开着。
    /// 不挡的话，自动隐藏档位下空闲计时照跑，任务条会从菜单底下缩掉。
    case taskbarMenuOpen
}

struct PanelVisibilityState: Equatable {
    var hideReasons: Set<PanelVisibilityReason> = []
    var autoHideInhibitors: Set<EdgeAutoHideInhibitor> = []
    private(set) var fullscreenTransitionGeneration: UInt64?

    var isVisible: Bool { hideReasons.isEmpty }

    mutating func setFullscreen(_ active: Bool) {
        setReason(.fullscreen, active: active)
    }

    mutating func beginFullscreenTransition(generation: UInt64) {
        fullscreenTransitionGeneration = generation
        hideReasons.insert(.fullscreenTransitionPending)
    }

    @discardableResult
    mutating func confirmFullscreenTransition(generation: UInt64) -> Bool {
        guard fullscreenTransitionGeneration == generation else { return false }
        fullscreenTransitionGeneration = nil
        hideReasons.remove(.fullscreenTransitionPending)
        hideReasons.insert(.fullscreen)
        return true
    }

    @discardableResult
    mutating func timeoutFullscreenTransition(generation: UInt64) -> Bool {
        guard fullscreenTransitionGeneration == generation else { return false }
        fullscreenTransitionGeneration = nil
        hideReasons.remove(.fullscreenTransitionPending)
        return true
    }

    mutating func setEdgeAutoHidden(_ active: Bool) {
        setReason(.edgeAutoHide, active: active)
    }

    mutating func setInhibitor(_ inhibitor: EdgeAutoHideInhibitor, active: Bool) {
        if active {
            autoHideInhibitors.insert(inhibitor)
        } else {
            autoHideInhibitors.remove(inhibitor)
        }
    }

    mutating func reconcileEdgeAutoHide(isEnabled: Bool) {
        if !isEnabled || !autoHideInhibitors.isEmpty {
            hideReasons.remove(.edgeAutoHide)
        }
    }

    private mutating func setReason(_ reason: PanelVisibilityReason, active: Bool) {
        if active {
            hideReasons.insert(reason)
        } else {
            hideReasons.remove(reason)
        }
    }
}

@MainActor
enum EdgeAutoHideRuntimeRules {
    static let fixedIdleHideDelay: Double = 0.2

    static func canArmWake(state: PanelVisibilityState, delay: Double) -> Bool {
        state.hideReasons.contains(.edgeAutoHide)
            && !state.hideReasons.contains(.fullscreen)
            && !state.hideReasons.contains(.fullscreenTransitionPending)
            && state.autoHideInhibitors.isEmpty
            && delay != AppSettingsStore.neverHideDelay
            && delay < AppSettingsStore.neverWakeDelay
    }

    static func canArmIdleHide(state: PanelVisibilityState, delay: Double) -> Bool {
        !state.hideReasons.contains(.edgeAutoHide)
            && !state.hideReasons.contains(.fullscreen)
            && !state.hideReasons.contains(.fullscreenTransitionPending)
            && state.autoHideInhibitors.isEmpty
            && delay != AppSettingsStore.neverHideDelay
    }

    static func idleHideInterval(for delay: Double) -> Double? {
        guard delay > AppSettingsStore.neverHideDelay else { return nil }
        return fixedIdleHideDelay
    }

    /// 底边唤醒热区（贯穿整条屏幕底边）是否应该压住 idle-hide、阻止武装隐藏计时器。
    /// 只在"有限唤醒延迟"（0.1–3.0s）时成立：这个区间唤醒和 idle-hide 都在跑，鼠标停在热区内、
    /// 但任务条矩形外时，两者会互相打架（唤醒→隐藏→唤醒…），必须让热区本身也算"没离开"。
    /// 999（`neverWakeDelay`，自动隐藏但不唤醒）没有唤醒动作，不存在这种打架，隐藏应照常进行；
    /// -1（`neverHideDelay`，常驻显示）本来就不会隐藏，压不压都一样。
    static func bottomHotZoneSuppressesIdleHide(delay: Double) -> Bool {
        delay != AppSettingsStore.neverHideDelay && delay < AppSettingsStore.neverWakeDelay
    }
}
