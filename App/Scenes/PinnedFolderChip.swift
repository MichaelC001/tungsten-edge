import AppKit
import SwiftUI

/// Pinned folder chip: the cover alone, at app-icon size in an icon-card slot, like a native
/// Dock stack. The name lives in the hover bubble (`DockStripView.bubbleTitle`) and in `.help`.
///
/// No name row under the cover: it shrank the cover to ~22pt against the neighbours' 32.5pt,
/// widened the card, and its black text with a white halo turned into a smudge on dark glass.
/// 点击一律 onTapGesture（nonactivatingPanel 上勿用 Button）；右键 = 手搓 NSMenu。
struct PinnedFolderChip: View {
    let path: String
    let cover: FolderCover?
    /// 当前排序方式（菜单打勾用;menu builder 每次右键现建,读到的总是最新值）。
    let sortOrder: FolderSortOrder
    let onTap: () -> Void
    /// 内容预览（右键「预览内容」；左键在 preview 模式下也走这个）。
    let onPreview: () -> Void
    /// 打开该路径访达窗口（右键「在访达中打开」；左键在 openFinderWindow 模式下也走这个）。
    let onOpenInFinder: () -> Void
    let onAddFolder: () -> Void
    let onRemove: () -> Void
    let onSetSortOrder: (FolderSortOrder) -> Void
    var isDropTarget = false
    /// 任务条尺寸档位的缩放系数。中档 = 1.0，此时所有尺寸与历史字面值逐像素相同。
    /// **故意不给默认值**——漏传必须是编译错误，见 AGENTS《Taskbar Size Tiers》。
    let scale: CGFloat
    /// 悬停效果档位。**同样故意不给默认值**——漏传必须是编译错误，理由同 `scale`。
    let hoverStyle: HoverStyle
    /// 指针在不在这张卡上。由任务条整条那块跟踪区算好后传进来（见 `StripHoverResolution`）；
    /// 拖动载体传 `false`。**故意不给默认值**，理由同 `scale` / `hoverStyle`。
    let isHovered: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var theme: DockThemeTokens { .resolved(for: colorScheme) }

    /// Hover behaves exactly like an app icon card: the standard tier changes no pixels (the
    /// name bubble is the feedback), the quiet tier gets the shared 1.10 bottom-anchored lift.
    /// `DockStripView.pickUpPose` reads the same rule for the drag carrier's first frame.
    private var quietHoverFeedback: Bool {
        hoverStyle.showsQuietHoverFeedback(isHovering: isHovered)
    }

    private var folderName: String {
        FileManager.default.displayName(atPath: path)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            coverSlot
            Spacer(minLength: 0)
        }
        .frame(width: ChipPillMetrics.cardWidth * scale,
               height: ChipPillMetrics.chipHeight * scale)
        .chipQuietHoverScale(quietHoverFeedback,
                             cardWidth: ChipPillMetrics.cardWidth * scale,
                             scale: scale)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .nativeContextMenu { buildMenu() }
        .help(folderName)
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
    }

    /// The icon-card slot (40pt) with the cover and the drop-target ring, lifted as one piece.
    private var coverSlot: some View {
        let slot = ChipPillMetrics.bareIconSlot * scale
        let visible = ChipPillMetrics.bareIconVisibleSlot * scale
        let corner = visible * Self.visibleCornerFraction
        return coverImage(slot: slot, visible: visible, corner: corner)
            .frame(width: slot, height: slot)
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(theme.folderDropRing.color(active: isDropTarget), lineWidth: 1.5)
                    .frame(width: visible, height: visible)
            }
            .scaleEffect(isDropTarget ? 1.08 : 1)
    }

    /// Same squircle fraction as the self-drawn shelf tile, so a thumbnail reads as an icon.
    private static let visibleCornerFraction: CGFloat = 0.215

    /// 封面：真缩略图满铺、方形裁切 + 细描边，按 app 图标的**可见方块**（32.5pt）画——
    /// 缩略图没有苹果图标资源那圈透明边距，按槽位画会比邻居大一圈；
    /// 文件图标 / 空文件夹图标自带留白，按槽位 fit 渲染，与 app 图标同口径。
    @ViewBuilder
    private func coverImage(slot: CGFloat, visible: CGFloat, corner: CGFloat) -> some View {
        if let cover, cover.isThumbnail {
            Image(nsImage: cover.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: visible, height: visible)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(theme.folderThumbHairline.color, lineWidth: 0.5)
                )
        } else {
            Image(nsImage: cover?.image ?? PinnedFolderCoverStore.icon(forPath: path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: slot, height: slot)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(String(localized: "Preview Contents")) { onPreview() })
        menu.addItem(ClosureMenuItem(String(localized: "Open in Finder")) { onOpenInFinder() })
        menu.addItem(.separator())
        // 排序方式 ▸（原生 Stacks 同款）：弹窗网格与 chip 封面都跟随,逐文件夹记忆。
        let sortItem = NSMenuItem(title: String(localized: "Sort by"), action: nil, keyEquivalent: "")
        let sortMenu = NSMenu()
        for order in FolderSortOrder.allCases {
            let item = ClosureMenuItem(order.menuTitle) { onSetSortOrder(order) }
            item.state = order == sortOrder ? .on : .off
            sortMenu.addItem(item)
        }
        sortItem.submenu = sortMenu
        menu.addItem(sortItem)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(String(localized: "Add Folder…")) { onAddFolder() })
        menu.addItem(ClosureMenuItem(String(localized: "Remove from Taskbar")) { onRemove() })
        return menu
    }
}
