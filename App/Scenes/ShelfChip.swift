import AppKit
import SwiftUI

/// 中转格：固定在文件夹区头位的暂存格。
/// 拖文件到格上松手即暂存（引用不搬家），点击弹出暂存网格。**不可拖拽**（固定头位）。
/// 视觉上采用普通 app 图标的圆角与阴影风格，不再使用文件夹的堆叠样式。
/// 数量**不做外凸角标**，改成悬停名字气泡里的文字，避免与固定区其余 chip 的"零装饰"视觉基调冲突。
struct ShelfChip: View {
    let itemCount: Int
    let isDropTargeted: Bool
    /// 任务条尺寸档位的缩放系数。中档 = 1.0，此时所有尺寸与历史字面值逐像素相同。
    /// **故意不给默认值**——漏传必须是编译错误，见 AGENTS《Taskbar Size Tiers》。
    let scale: CGFloat
    /// 悬停效果档位。**同样故意不给默认值**——漏传必须是编译错误，理由同 `scale`。
    let hoverStyle: HoverStyle
    let onTap: () -> Void
    let onClear: () -> Void
    let onAddFolder: () -> Void

    /// 浅 / 深色两套视觉数值（见 `DockThemeTokens`）。
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DockThemeTokens { .resolve(colorScheme) }

    @State private var isHovering = false

    /// 悬停视觉的总闸：「安静」档下恒 false，图标不缩、名字气泡不出。
    /// 投放反馈（`isDropTargeted` 的提亮/描边/发光）不受它管。
    private var showsHover: Bool { hoverStyle.isExpressive && isHovering }

    /// 件数原本只写在悬停名字里，安静档下那行不出现，所以并进系统 tooltip 兜底。
    /// 两档都生效，条上不改变任何像素。
    private var helpText: String {
        itemCount > 0 ? "中转 · \(itemCount)：拖文件到这里暂存" : "中转：拖文件到这里暂存"
    }

    var body: some View {
        let coverSize: CGFloat = (showsHover ? 24 : 36) * scale
        VStack(spacing: 2 * scale) {
            Spacer(minLength: 0)
            shelfIcon(size: coverSize)
            if showsHover {
                Text(itemCount > 0 ? "中转 · \(itemCount)" : "中转")
                    .font(.system(size: 10 * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.labelHover.color)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(width: ChipPillMetrics.cardWidth * scale,
               height: ChipPillMetrics.chipHeight * scale)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
        .nativeContextMenu { buildMenu() }
        .help(helpText)
        .animation(.easeInOut(duration: 0.18), value: showsHover)
        .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
    }

    /// 固定入口图标：外层保持普通 app chip 的 36/24 槽位，内部半透明底板缩到视觉尺寸。
    /// 投放反馈：在内部底板进行提亮与加亮描边，消除外层大框。
    private func shelfIcon(size: CGFloat) -> some View {
        // 判据用缩放前的槽位，避免小档时 36×0.85=30.6 掉进「悬停态」分支。
        let innerSize: CGFloat = (size / scale > 30 ? 32 : 22) * scale

        return ZStack {
            RoundedRectangle(cornerRadius: innerSize / 4, style: .continuous)
                .fill(theme.shelfPlateFill.color(emphasized: isDropTargeted))
                .overlay(
                    RoundedRectangle(cornerRadius: innerSize / 4, style: .continuous)
                        .strokeBorder(theme.shelfPlateRim.color(emphasized: isDropTargeted), lineWidth: 0.5)
                )
                .dockGlow(theme.shelfDropGlow, radius: 2, active: isDropTargeted)
            Image(systemName: "tray.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: innerSize * 0.46, height: innerSize * 0.46)
                .foregroundStyle(theme.shelfGlyph.color)
        }
        .frame(width: innerSize, height: innerSize)
        .dockShadow(theme.iconShadow)
        .frame(width: size, height: size)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("打开中转") { onTap() })
        if itemCount > 0 {
            menu.addItem(ClosureMenuItem("清空中转") { onClear() })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("添加文件夹…") { onAddFolder() })
        return menu
    }
}
