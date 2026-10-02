import AppKit
import SwiftUI

struct TrashChip: View {
    let isFull: Bool
    let isDropTargeted: Bool
    let scale: CGFloat
    let hoverStyle: HoverStyle
    let isHovered: Bool
    let menuItems: [TrashMenuPlan.Item]
    let onTap: () -> Void
    let onOpen: () -> Void
    let onEmpty: () -> Void
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: TrashIconArt.image(isFull: isFull, colorScheme: colorScheme))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: ChipPillMetrics.bareIconSlot * scale, height: ChipPillMetrics.bareIconSlot * scale)
            .frame(width: ChipPillMetrics.cardWidth * scale, height: ChipPillMetrics.chipHeight * scale)
            .scaleEffect(isDropTargeted ? 1.08 : 1, anchor: .bottom)
            .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
            .chipQuietHoverScale(hoverStyle.showsQuietHoverFeedback(isHovering: isHovered),
                                 cardWidth: ChipPillMetrics.cardWidth * scale, scale: scale)
            .chipPressScale(isPressed)
            .contentShape(Rectangle())
            // Same order as LauncherChip: the tap sits inside the press gesture. Reversed, the
            // inner zero-distance drag outranks the outer tap and clicks stop opening the Trash.
            .onTapGesture(perform: onTap)
            .chipPressGesture(isPressed: $isPressed)
            .nativeContextMenu { buildMenu() }
            .help(String(localized: "Trash"))
            .accessibilityLabel(String(localized: "Trash"))
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in menuItems {
            switch item {
            case .open:
                menu.addItem(ClosureMenuItem(String(localized: "Open Trash"), handler: onOpen))
            case let .empty(enabled):
                let row = ClosureMenuItem(String(localized: "Empty Trash…"), handler: onEmpty)
                row.isEnabled = enabled
                menu.addItem(row)
            }
        }
        return menu
    }
}

/// The Trash icon is the light one in both appearances, as on the native Dock. The system image
/// carries a dark rendition that AppKit picks under `darkAqua` — and SwiftUI's `colorScheme`
/// environment does not override that choice — so in dark the light rendition is resolved
/// explicitly. In light the system image is used untouched, which keeps that look pixel-identical.
enum TrashIconArt {
    static func image(isFull: Bool, colorScheme: ColorScheme) -> NSImage {
        if colorScheme == .dark { return isFull ? lightFull : lightEmpty }
        return NSImage(named: isFull ? NSImage.trashFullName : NSImage.trashEmptyName) ?? NSImage()
    }

    static let lightEmpty = resolveLight(NSImage.trashEmptyName)
    static let lightFull = resolveLight(NSImage.trashFullName)

    private static func resolveLight(_ name: NSImage.Name) -> NSImage {
        guard let source = NSImage(named: name) else { return NSImage() }
        var resolved: CGImage?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            var rect = CGRect(origin: .zero, size: CGSize(width: 512, height: 512))
            resolved = source.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        return resolved.map { NSImage(cgImage: $0, size: source.size) } ?? source
    }
}
