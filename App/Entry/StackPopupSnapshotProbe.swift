import AppKit
import SwiftUI

/// `DOCK_STACK_POPUP_SNAPSHOT=<folder>`: draws that folder's popup content — the real
/// `FolderGridPopupView`, sorted by name as the native Dock sorts — in a window parked far
/// off-screen and writes it to `<tmp>/tungsten-stack-popup.png`, so titles, icons, thumbnails and
/// names can be diffed against a native capture without anyone clicking. `shelf` and `trash`
/// instead of a path draw those two popups. The plate is not in the
/// picture (glass and frosted backdrops only exist composited on screen); neither is anything
/// blended against it.
@MainActor
enum StackPopupSnapshotProbe {
    private static var window: NSWindow?

    static func runIfRequested() {
        guard let folder = DebugSwitch.stackPopupSnapshot.value(), !folder.isEmpty else { return }
        let url = URL(fileURLWithPath: folder)
        let isFolder = folder != "shelf" && folder != "trash"
        let entries = isFolder
            ? FolderContentsLoader.sorted((try? FolderContentsLoader.load(directory: url)) ?? [], by: .name)
            : []
        FolderIconResolver.warm(paths: entries.map(\.url.path), timeout: 2)
        let screen = NSScreen.main?.frame.size ?? CGSize(width: 1352, height: 878)
        let context = StackPopupContext(
            limits: StackGridLayout.limits(screenSize: screen, availablePlateHeight: screen.height - 110),
            arrow: StackPopupArrowModel())
        var failures: [String] = []
        let lock = NSLock()
        FolderIconResolver.onThumbnailFailure = { line in lock.lock(); failures.append(line); lock.unlock() }
        let content: AnyView
        switch folder {
        case "shelf":
            content = AnyView(ShelfGridPopupView(shelfStore: ShelfStore(), context: context, usesLiquidGlass: false))
        case "trash":
            content = AnyView(TrashGridPopupView(trashStore: .shared, context: context, usesLiquidGlass: false))
        default:
            content = AnyView(FolderGridPopupView(rootURL: url, initialEntries: entries, sortOrder: .name,
                                                  context: context, usesLiquidGlass: false))
        }
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.orderFrontRegardless()
        Self.window = window
        // Thumbnails arrive asynchronously; give them time before drawing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tungsten-stack-popup.png")
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: output)
            }
            lock.lock()
            let report = (["\(entries.count) entries, window \(size.width)x\(size.height), scale \(hosting.window?.backingScaleFactor ?? 0)"] + failures)
                .joined(separator: "\n")
            lock.unlock()
            try? report.write(to: output.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
            FolderIconResolver.onThumbnailFailure = nil
            window.orderOut(nil)
            Self.window = nil
        }
    }
}
