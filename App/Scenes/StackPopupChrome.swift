import AppKit
import SwiftUI

/// Where the popup's arrow points. The coordinator owns it and rewrites it with every frame it
/// gives the popup window: once the plate is clamped at a screen edge it is no longer centred on
/// its chip, and the arrow has to stay on the chip.
@MainActor
final class StackPopupArrowModel: ObservableObject {
    /// Arrow centre minus plate centre, in points.
    @Published var offsetFromCenter: CGFloat = 0
}

/// What the coordinator knows and a popup's content needs: how large the grid may get on this
/// screen, and the arrow.
struct StackPopupContext {
    let limits: StackGridLayout.Limits
    let arrow: StackPopupArrowModel
}

/// The frame shared by the folder, shelf and Trash popups, laid out like the native Dock's stack
/// grid: title row, optional status line, grid, and the plate with its arrow. Width and height are
/// derived from `layout` — never measured.
struct StackPopupChrome<Grid: View>: View {
    let title: String
    /// A line between title and grid; the native grid has none (empty shelf, Trash state).
    let note: String?
    let layout: StackGridLayout.Result
    let usesLiquidGlass: Bool
    @ObservedObject var arrow: StackPopupArrowModel
    /// Non-nil shows the back button (drilled into a subfolder).
    var onBack: (() -> Void)?
    /// Animates cells arriving and leaving; nil while the first population lands.
    var gridAnimation: Animation?
    var gridAnimationKey: [URL] = []
    /// The cells; they land in a `LazyVGrid` of `layout.columns` fixed columns.
    @ViewBuilder let grid: () -> Grid

    private let theme = DockThemeTokens.standard
    private typealias Metrics = StackPopupMetrics

    private var plateSize: CGSize {
        Metrics.plateSize(columns: layout.columns, rows: layout.visibleRows, hasNote: note != nil)
    }
    private var gridWidth: CGFloat { CGFloat(layout.columns) * Metrics.cell }
    private var gridHeight: CGFloat { CGFloat(layout.visibleRows) * Metrics.cell }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let note { noteLine(note) }
            gridArea
        }
        .frame(width: plateSize.width, height: plateSize.height, alignment: .top)
        .background(alignment: .top) {
            StackPopupBackdrop(plateSize: plateSize,
                               arrowCenterX: plateSize.width / 2 + arrow.offsetFromCenter,
                               usesLiquidGlass: usesLiquidGlass)
        }
        .padding(.bottom, Metrics.arrowHeight)
        .padding(Metrics.panelMargin)
        // Only so the system scroller draws its light knob on this dark plate; nothing reads it.
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        Text(title)
            .font(.system(size: Metrics.titleSize))
            .foregroundStyle(theme.stackPopupText.color)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 44)
            .frame(width: plateSize.width, height: Metrics.headerHeight)
            .offset(y: Metrics.titleCenterY - Metrics.headerHeight / 2)
            .overlay(alignment: .topLeading) { backButton }
    }

    @ViewBuilder
    private var backButton: some View {
        if let onBack {
            Group {
                if let art = NativeStackArtwork.backButton {
                    Image(nsImage: art).blendMode(.plusLighter)
                } else {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.stackPopupText.color)
                        .frame(width: Metrics.backButtonSize.width, height: Metrics.backButtonSize.height)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(theme.stackPopupBackFill.color))
                }
            }
            .frame(width: Metrics.backButtonSize.width, height: Metrics.backButtonSize.height)
            // A 21pt target is the native size; the hit area reaches the plate's corner.
            .padding(.leading, Metrics.backButtonOrigin.x)
            .padding(.top, Metrics.backButtonOrigin.y)
            .padding([.trailing, .bottom], 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onBack)
            .help(Text("Back"))
        }
    }

    private func noteLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Metrics.labelSize))
            .foregroundStyle(theme.stackPopupNote.color)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Metrics.sidePadding)
            .frame(width: plateSize.width, height: Metrics.noteHeight)
    }

    @ViewBuilder
    private var gridArea: some View {
        let columns = Array(repeating: GridItem(.fixed(Metrics.cell), spacing: 0), count: layout.columns)
        let cells = LazyVGrid(columns: columns, alignment: .leading, spacing: 0, content: grid)
            .frame(width: gridWidth, alignment: .leading)
            .animation(gridAnimation, value: gridAnimationKey)
        if layout.scrolls {
            ScrollView(.vertical, showsIndicators: true) {
                cells.frame(width: gridWidth + Metrics.scrollerGutter, alignment: .leading)
            }
            .frame(width: gridWidth + Metrics.scrollerGutter, height: gridHeight)
            .padding(.leading, Metrics.sidePadding)
        } else {
            cells
                .frame(height: gridHeight, alignment: .top)
                .padding(.leading, Metrics.sidePadding)
        }
    }
}
