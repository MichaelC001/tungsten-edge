import Foundation

/// 任务条屏幕安放模式（多屏显示第一步，2026-08-26）。
/// rawValue 即 UserDefaults 持久化值；将来的「所有屏幕」档在这里加 case。
/// **与已删除的旧 `com.tungsten.edge.displayMode` 键无关**——那个键是孤儿键，永不再读。
enum TaskbarScreenMode: String {
    case followMouse
    case pinned
}

/// 固定屏的持久化身份。`uuid` 来自 `CGDisplayCreateUUIDFromDisplayID`（基于 EDID，
/// 拔插 / 换口 / 休眠唤醒后稳定）；`name` 是选择那一刻 `localizedName` 的快照，
/// **只供设置页展示**（屏幕拔掉后 Picker 里还能显示「XX（未连接）」），永不参与匹配。
struct PinnedScreenSelection: Equatable {
    let uuid: String
    let name: String
}

/// 任务条显示位置。默认 `.followMouse` = 现状行为（底边停留切屏）。
enum TaskbarScreenPlacement: Equatable {
    case followMouse
    case pinned(PinnedScreenSelection)

    /// 悬停切屏（底边停留搬 dock）只在跟随鼠标档生效。
    var allowsHoverScreenSwitching: Bool {
        self == .followMouse
    }

    var mode: TaskbarScreenMode {
        switch self {
        case .followMouse: return .followMouse
        case .pinned: return .pinned
        }
    }

    var pinnedSelection: PinnedScreenSelection? {
        switch self {
        case .followMouse: return nil
        case .pinned(let selection): return selection
        }
    }
}

/// 固定屏 → 当前屏幕集合的纯解析。运行时不存任何额外状态：每次屏幕参数变化 /
/// 设置变更时幂等地重解析一遍，屏一回来自然搬回去。
enum TaskbarScreenResolution {
    enum Outcome: Equatable {
        /// 固定的屏在场，落在该下标。
        case matched(index: Int)
        /// 固定的屏缺席，回落主屏（无主屏则 0）。
        case fallback(index: Int)
    }

    /// - Parameters:
    ///   - pinnedUUID: 存下来的固定屏 UUID。
    ///   - screenUUIDs: 当前 `NSScreen.screens` 逐个读出的 UUID；读不出的为 nil（不误匹配）。
    ///   - mainIndex: `NSScreen.main` 在 screens 里的下标（可能为 nil）。
    /// - Returns: 屏幕集合为空时返回 nil（无处可放，交调用方兜底）。
    static func resolve(pinnedUUID: String, screenUUIDs: [String?], mainIndex: Int?) -> Outcome? {
        guard !screenUUIDs.isEmpty else { return nil }
        if let index = screenUUIDs.firstIndex(where: { $0 == pinnedUUID }) {
            return .matched(index: index)
        }
        if let mainIndex, screenUUIDs.indices.contains(mainIndex) {
            return .fallback(index: mainIndex)
        }
        return .fallback(index: 0)
    }

    /// 设置页 Picker 的展示名去重：两台同型号显示器同名时，第二台起加序号
    /// （「LG HDR 4K」「LG HDR 4K (2)」）。顺序与输入一致。
    static func displayTitles(names: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for name in names {
            counts[name, default: 0] += 1
        }
        var seen: [String: Int] = [:]
        return names.map { name in
            guard counts[name, default: 0] > 1 else { return name }
            let ordinal = seen[name, default: 0] + 1
            seen[name] = ordinal
            return ordinal == 1 ? name : "\(name) (\(ordinal))"
        }
    }
}

/// 状态菜单「钨极 Dock 栏显示在 ▸」子菜单的纯展示模型（2026-08-26 入口从设置窗口搬到菜单）。
/// 与 `LaunchAtLoginMenuPresentation` 同一房规：判定在这里、可单测，controller 只负责渲染。
struct TaskbarScreenMenuPresentation {
    struct Item: Equatable {
        /// nil = 「跟随鼠标」；否则是那块屏的 display UUID。
        let uuid: String?
        let title: String
        let isChecked: Bool
    }

    /// 整行（连同子菜单）不显示。
    let isHidden: Bool
    let items: [Item]

    /// - Parameter connectedScreens: 当前在场的屏，`title` 已去重（`displayTitles`）。
    init(placement: TaskbarScreenPlacement, connectedScreens: [(uuid: String, title: String)]) {
        let pinned = placement.pinnedSelection
        // 只有一块屏**且**当前不是固定档才隐藏。少了后半句会出死角：固定到外接屏后把它拔掉，
        // 就只剩一块屏 → 整行消失 → 再也切不回「跟随鼠标」。
        isHidden = connectedScreens.count < 2 && pinned == nil

        var items: [Item] = [
            Item(uuid: nil, title: String(localized: "Follow the mouse"), isChecked: pinned == nil)
        ]
        items += connectedScreens.map { screen in
            Item(uuid: screen.uuid, title: screen.title, isChecked: pinned?.uuid == screen.uuid)
        }
        // 固定的屏此刻不在场：末尾补一项「XX（未连接）」并保持选中——选择不丢，接回自动生效。
        if let pinned, !connectedScreens.contains(where: { $0.uuid == pinned.uuid }) {
            items.append(
                Item(
                    uuid: pinned.uuid,
                    title: String(format: String(localized: "%@ (disconnected)"), pinned.name),
                    isChecked: true
                )
            )
        }
        self.items = items
    }
}
