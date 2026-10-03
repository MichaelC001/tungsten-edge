import CoreGraphics
import Foundation

/// 外部文件拖入任务条的落点路由（纯函数，进单测）。
///
/// 所有输入坐标都在 `"strip"` 空间——`onDrop` 必须挂在**定义该坐标空间的同一层视图**上
/// （评审拍板：DropDelegate 的 location 与 `geo.frame(in: .named("strip"))` 必须同源，
/// 绝不能挂到 `.padding(shadowPadding)` 之后的内外层）。只做水平路由：拖到任务条上即算
/// 有效高度，垂直命中由 onDrop 挂载层保证。
enum StripDropRouting {
    /// 中档基线。任务条缩放后调用方传 `defaultHeadSlack * scale`。
    static let defaultHeadSlack: CGFloat = 8

    enum Target: Equatable {
        /// 落在中转格 → 暂存（任何文件/文件夹，引用不搬家）。
        case stash
        case trash
        /// 落在某个固定文件夹 chip → 把来源移入该文件夹。
        case moveInto(path: String)
        /// 落在文件夹区 → 固定目录到显示序 index 位（仅目录有效，由调用方过滤）。
        case pin(insertIndex: Int)
        /// 拖的是应用 bundle → 勾「在程序坞中保留」+ 落到光标那个位置。**整条都是它的落点**，
        /// 不带 index：live 区的插入位由 `StripBlockLanding` 按 `chipFrames` 算（见 `handleExternalApplicationDrop`）。
        case keepApp
        /// 其他位置 → 拒绝。
        case none
    }

    /// - Parameters:
    ///   - location: drop 落点（"strip" 空间）。
    ///   - isApplicationDrag: 这次拖的是不是应用 bundle。**没有默认值**：漏传会静默编译成
    ///     「应用走文件分支」，而那正是本参数存在的理由——`.app` 在文件系统里就是目录，
    ///     `.moveInto` 是真实的文件移动/跨卷复制，会把用户的应用从「应用程序」里搬走。
    ///     纯函数入参而不是在这里读盘，是为了让这条安全边界能进单测。
    ///   - isTrashItemDrag: every dragged URL is inside a Trash (`TrashPath`). **No default**, for
    ///     the same reason as `isApplicationDrag`: an omission would compile into "stash a reference
    ///     into the Trash" or "move a Trash item with our own file access". Checked before the app gate.
    ///   - shelfFrame: 中转格 frame（独立 PreferenceKey 上报，**不混入 folderFrames**）。
    ///     **nil = 用户关掉了中转格**。调用方必须直接按设置传 `showShelf ? frame : nil`，
    ///     不能等 PreferenceKey 把旧帧清掉——`ShelfFramePreferenceKey.reduce` 刻意忽略 `.zero`，
    ///     旧帧会一直留着，关掉后落在原位置仍会误判成 `.stash`。
    ///   - folderFrames: 文件夹 chip 帧（键 = StripEntry id，即 "folder-<path>"）。
    ///   - orderedPaths: 当前固定文件夹显示序（PinnedFolderStore.folderPaths）。
    ///   - headSlack: 第一个文件夹**左侧**仍算文件夹区的余量。它是「插到第 0 位」的唯一落点——
    ///     首个 chip 整段会先被判成 `.moveInto`，不留这段就永远插不到最前面。还没有文件夹时
    ///     它挂在废纸篓左侧，是第一次固定的落点。
    ///   - tailSlack: 最后一个文件夹右侧仍算文件夹区的余量。The Trash, when shown, sits right
    ///     after the zone and wins from its left edge on, so the slack only exists without it.
    ///   - pinEdgeFraction: the share of each chip's width, on both sides, that pins beside the chip
    ///     instead of moving into it. `0` keeps the whole chip a move-into target; a folders-only
    ///     drag (`dragPinsFolders`) passes `folderPinEdgeFraction`, or the only way to open the
    ///     make-way gap between two chips would be their 2pt spacing.
    ///   - openGap: the make-way gap currently open in the folder zone. It reports no frame, so at
    ///     either end of the zone its width has to be added to the slack — otherwise the pointer
    ///     resting inside the gap is outside the zone, the gap closes, and the two states loop.
    static func route(location: CGPoint,
                      isApplicationDrag: Bool,
                      isTrashItemDrag: Bool,
                      shelfFrame: CGRect?,
                      trashFrame: CGRect?,
                      folderFrames: [String: CGRect],
                      orderedPaths: [String],
                      headSlack: CGFloat = defaultHeadSlack,
                      tailSlack: CGFloat = 24,
                      pinEdgeFraction: CGFloat = 0,
                      openGap: OpenFolderGap? = nil) -> Target {
        // Trash items are refused everywhere on the bar, the Trash chip and app landing included.
        if isTrashItemDrag { return .none }

        // ⚠️ 安全闸，紧跟废纸篓那一句：应用永远走保留，绝不落到 .moveInto / .pin / .stash。
        // 整条任务条都是它的落点——用户的直觉是「拖到 Dock 上」，落在窗口区必须算数。
        if isApplicationDrag { return .keepApp }

        if let trashFrame, trashFrame != .zero, location.x >= trashFrame.minX { return .trash }

        // The shelf is its own target, away from the folders (last cell of the pinned-app zone).
        if let shelfFrame {
            guard shelfFrame != .zero else { return .none }   // 中转格开着但帧未就绪（首帧）不接
            if location.x >= shelfFrame.minX, location.x <= shelfFrame.maxX { return .stash }
        }

        let frames = orderedPaths.compactMap { folderFrames["folder-" + $0] }

        // 文件夹区左边界：首个文件夹左侧的 headSlack。还没有文件夹时退到废纸篓左缘——区里只有
        // 废纸篓，它左边那段 headSlack 是「第一次拖目录进来固定」的唯一落点。两者都没有 →
        // 固定区根本不存在，拒绝。
        let trashMinX = trashFrame.flatMap { $0 != .zero ? $0.minX : nil }
        guard let zoneMinX = frames.map(\.minX).min() ?? trashMinX else { return .none }
        let headGap = openGap.map { $0.insertIndex <= 0 ? $0.width : 0 } ?? 0
        if location.x < zoneMinX - headSlack - headGap { return .none }

        // onDrop 覆盖整条任务条的有效高度，路由保持既有的纯水平语义；不能用 contains，
        // 否则 chip 上下留白会意外退回 pin。
        if let path = orderedPaths.first(where: { path in
            guard let frame = folderFrames["folder-" + path] else { return false }
            let edge = frame.width * min(max(pinEdgeFraction, 0), 0.5)
            return location.x >= frame.minX + edge && location.x <= frame.maxX - edge
        }) {
            return .moveInto(path: path)
        }

        let tailGap = openGap.map { $0.insertIndex >= frames.count ? $0.width : 0 } ?? 0
        guard location.x <= (frames.map(\.maxX).max() ?? zoneMinX) + tailSlack + tailGap else { return .none }

        // 插入序号 = 中点在落点左侧的文件夹个数（落在某 chip 左半边 → 插它前面）。
        let index = orderedPaths.filter { path in
            guard let frame = folderFrames["folder-" + path] else { return false }
            return frame.midX < location.x
        }.count
        return .pin(insertIndex: index)
    }
}

/// 从访达拖应用或文件夹进条时、悬停期让位让出来的那个空档。
///
/// **存的是插入序号，不是「哪张卡的左/右」**，这一点是载重的。空档一插进去，它右边所有
/// 卡片都往右挪了一张卡的宽度；下一次 `dropUpdated` 量到的就是挪过之后的帧。指针停在空档
/// 里时左右两张卡等距，`StripBlockLanding` 会在「左邻的右边」和「右邻的左边」之间摇摆——
/// 这两者**指的是同一个空位**，但作为 `(id, after)` 二元组并不相等。存二元组的话，门控就会
/// 让一串「位置没变却重算整条任务条」的写入漏过去（这仓库实测过「1.2 秒拖动 46 次整条重算」）。
/// 折成序号，两种说法归一，门控才真的挡得住。
struct StripDropGhost: Equatable {
    enum Zone: Equatable {
        /// An app dragged in: the gap opens among the live-zone cards.
        case live(bundleID: String)
        /// A folder dragged in: the gap opens among the pinned folders.
        case folder
    }
    let zone: Zone
    /// 空档插在所在区显示序的第几位（live 区的卡 / 固定文件夹，都不含中转格）。
    let insertIndex: Int
}

extension StripDropRouting {
    /// Share of a folder chip's width, on each side, that pins beside it while a folder is dragged.
    static let folderPinEdgeFraction: CGFloat = 0.25

    /// The make-way gap open among the pinned folders, as `route` needs it.
    struct OpenFolderGap: Equatable {
        /// Position among the pinned folders (the shelf is not counted).
        let insertIndex: Int
        /// Layout width the gap adds: one card plus one chip spacing.
        let width: CGFloat
    }

    /// Whether a drag gets the folder-pin behaviour (gap, pin edges, no badge): every item that is
    /// not an app is a directory. One plain file among them keeps the old routing for the whole
    /// drag — on a chip's edge it would otherwise be left behind while the folders pin.
    static func dragPinsFolders(nonApplicationItemsAreDirectories: [Bool]) -> Bool {
        !nonApplicationItemsAreDirectories.isEmpty && nonApplicationItemsAreDirectories.allSatisfy { $0 }
    }

    /// The folder-zone gap for a hover target (pure, unit-tested). A pin target opens it at its
    /// index; a move-into target keeps the gap where it is — closing it would slide the chips back
    /// under a pointer that has not moved and hand the drop to the neighbour; anything else closes it.
    static func folderGhostIndex(current: Int?, target: Target, pinsFolder: Bool) -> Int? {
        guard pinsFolder else { return nil }
        switch target {
        case let .pin(insertIndex): return insertIndex
        case .moveInto: return current
        case .stash, .trash, .keepApp, .none: return nil
        }
    }

    /// `StripBlockLanding` 的（锚点卡, 左/右）折成插入序号（纯函数，进单测）。
    /// 锚点不在当前显示序里（那张卡刚消失 / 被换屏过滤掉）→ 落末尾，绝不返回越界下标。
    static func ghostInsertionIndex(orderedIDs: [String], targetID: String?, after: Bool) -> Int {
        guard let targetID, let index = orderedIDs.firstIndex(of: targetID) else {
            return orderedIDs.count
        }
        return after ? index + 1 : index
    }

    /// Whether the strip answers a drag with the generic operation (no cursor badge) instead of
    /// SwiftUI's `.copy` (the green plus). Over the Trash, where Tungsten Edge moves the file
    /// itself, and over a pin slot while a folder is dragged, where nothing is copied at all:
    /// `.copy` reads as "a copy goes in", and `.move` is never an option — it tells the source
    /// the item left, and Finder deletes an app it dragged in. A source that does not offer generic
    /// (e.g. ⌥ held) keeps `.copy`.
    static func usesGenericOperation(hoveredTarget: Target?, pinsFolder: Bool,
                                     proposedIsCopy: Bool, sourceAllowsGeneric: Bool) -> Bool {
        guard proposedIsCopy, sourceAllowsGeneric else { return false }
        switch hoveredTarget {
        case .trash: return true
        case .pin: return pinsFolder
        default: return false
        }
    }

    /// The URLs a drop commits. The item providers are the authority; only when **none** of them
    /// yields a URL does the drop fall back to the drag pasteboard snapshot — an in-process drag
    /// (our folder / shelf popup) may not coerce to `URL` at all.
    /// Trash items are dropped from either source (second gate; the first is the hover route).
    static func committedURLs(loaded: [URL?], pasteboard: [URL], homeDirectory: URL) -> [URL] {
        let resolved = loaded.compactMap { $0 }
        return (resolved.isEmpty ? pasteboard : resolved)
            .filter { !TrashPath.isInsideTrash($0, homeDirectory: homeDirectory) }
    }
}
