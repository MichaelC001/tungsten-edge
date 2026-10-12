import AppKit
import SwiftUI

/// Takes app bundles dragged from outside (Finder) onto the drawer capsule or into the open
/// drawer. Plain AppKit rather than SwiftUI `.onDrop`: each target is one zone with no coordinate
/// space to share, and only AppKit can answer `.generic` (no "+" badge, as for an app dragged
/// onto the strip).
///
/// The capsule's parent sizes it to the visible capsule + `DrawerAppDrop.capsuleTolerance`, so its
/// bounds are the zone; the drawer overlays its whole window and passes the plate as `zone`.
struct DrawerAppDropReceiver: NSViewRepresentable {
    /// The zone that lights and lands, in screen coordinates; nil = the view's own bounds.
    let screenZone: (() -> CGRect)?
    let onHoverChange: (Bool) -> Void
    /// The pointer in screen coordinates while the zone takes the drag; `nil` once it does not
    /// (left, refused, session over). The drawer opens its make-way slot from it; the capsule
    /// passes `{ _ in }`. Not sent `nil` on an accepted drop: the slot is handed to the landing.
    let onHoverLocation: (CGPoint?) -> Void
    /// The drawer cell an app's drag image turns into while the zone takes the drag; `nil` keeps
    /// the source's image (the capsule). No default — an omission would compile into a drawer whose
    /// drag image never changes.
    let dragImage: ((String) -> DrawerDragImage?)?
    /// The accepted bundles, the release point in screen coordinates, and where the first app's
    /// drag image was let go (`DrawerDropLanding`) for the carrier to take over from.
    let onDropApplications: ([URL], CGPoint, DrawerDropLanding?) -> Void

    func makeNSView(context: Context) -> DrawerAppDropView { DrawerAppDropView() }

    func updateNSView(_ view: DrawerAppDropView, context: Context) {
        view.screenZone = screenZone
        view.onHoverChange = onHoverChange
        view.onHoverLocation = onHoverLocation
        view.dragImage = dragImage
        view.onDropApplications = onDropApplications
    }

    static func dismantleNSView(_ view: DrawerAppDropView, coordinator: ()) { view.endSession() }
}

/// A drawer cell bitmap for the system drag image: the image (bleed included) and the icon's rect
/// inside it, y up (`DrawerDragImageGeometry.iconRect`).
struct DrawerDragImage {
    let image: NSImage
    let iconRect: CGRect
}

/// Where the first dropped app's drag image was let go, in screen coordinates: the drawer cell
/// frame the receiver asked for (not read back — the system shows it ~0.3s late, `Docs/05`), or on
/// the capsule the source image's icon.
struct DrawerDropLanding {
    let bundleID: String
    let screenFrame: CGRect
}

final class DrawerAppDropView: NSView {
    var screenZone: (() -> CGRect)?
    var onHoverChange: (Bool) -> Void = { _ in }
    var onHoverLocation: (CGPoint?) -> Void = { _ in }
    var dragImage: ((String) -> DrawerDragImage?)?
    var onDropApplications: ([URL], CGPoint, DrawerDropLanding?) -> Void = { _, _, _ in }

    /// An item whose image this session swapped for a cell: what it showed before, and where both
    /// frames sit relative to the pointer (the item moves with it).
    private struct SwappedItem {
        let components: [NSDraggingImageComponent]
        let size: CGSize
        let offset: CGVector
        var cellOffset: CGVector
        var cellSize: CGSize
    }
    private var swappedItems: [Int: SwappedItem] = [:]
    private var showsCells = false

    /// Only `draggingEntered` opens a session. The system can send a stray `draggingUpdated`
    /// after a drop has ended; without this gate it would light the capsule again.
    private var isSessionLive = false
    private var isTargeted = false
    private var watchdog: Timer?

    /// A session that ends without any closing callback still goes dark this long after the last
    /// update (periodic updates keep arriving while the pointer rests).
    private static let watchdogInterval: TimeInterval = 0.35

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Drags only; clicks, right clicks and scrolling go to the cells and receivers beneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isSessionLive = true
        return evaluate(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isSessionLive else { return [] }
        return evaluate(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        // The system never puts the source image back, and a restore asked for just before the
        // pointer left is not shown (`Docs/05`): always restore once more here.
        if let sender, !swappedItems.isEmpty { restoreSourceImages(sender) }
        endSession()
    }

    /// Off on an accepted drop: the drag image vanishes on release instead of hanging over the
    /// target while the app appears in its cell.
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isSessionLive, isTargeted else { return false }
        sender.animatesToDestination = false
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let accepted = isSessionLive && isTargeted
        let point = screenPoint(sender)
        let landing = accepted ? dropLanding(sender) : nil
        // The exit report goes out before the landing: the spring-load's `.dropped` must be the
        // last word, so the drawer stays open on the app it just took.
        endSession(isLanding: true)
        guard accepted else { onHoverLocation(nil); return false }
        let dragged = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        // Trash items are dropped before the app check, as on the strip; plain files are not ours.
        let applications = dragged
            .filter { $0.isFileURL && !StripFileDropDelegate.DragPasteboardInspector.isInsideTrash($0) }
            .filter(StripFileDropDelegate.DragPasteboardInspector.isApplication)
        guard !applications.isEmpty else { onHoverLocation(nil); return false }
        onDropApplications(applications, point, landing)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        endSession()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        endSession()
    }

    /// `isLanding`: only an accepted drop — the hover point is not cleared, so the drawer's slot
    /// is still there for the landing to take over in the same turn.
    func endSession(isLanding: Bool = false) {
        isSessionLive = false
        swappedItems = [:]
        showsCells = false
        watchdog?.invalidate()
        watchdog = nil
        setTargeted(false, reportsLocation: !isLanding)
    }

    private func screenPoint(_ sender: NSDraggingInfo) -> CGPoint {
        window?.convertPoint(toScreen: sender.draggingLocation) ?? sender.draggingLocation
    }

    private func evaluate(_ sender: NSDraggingInfo) -> NSDragOperation {
        let containsApplication = StripFileDropDelegate.DragPasteboardInspector.containsApplication()
        let accepts: Bool
        if let screenZone {
            accepts = DrawerAppDrop.accepts(containsApplication: containsApplication,
                                            point: screenPoint(sender), zone: screenZone())
        } else {
            accepts = DrawerAppDrop.accepts(containsApplication: containsApplication,
                                            point: convert(sender.draggingLocation, from: nil), zone: bounds)
        }
        let wasTargeted = isTargeted
        setTargeted(accepts, reportsLocation: true)
        if accepts { onHoverLocation(screenPoint(sender)) }
        // After the location: the drawer opens its slot there, and the cell bitmaps come from it.
        if accepts, !wasTargeted, dragImage != nil {
            swapInCellImages(sender)
        } else if !accepts, wasTargeted, showsCells {
            restoreSourceImages(sender)
        }
        armWatchdog()
        guard accepts else { return [] }
        return sender.draggingSourceOperationMask.contains(.generic) ? .generic : .copy
    }

    // MARK: - The drag image

    private func pointer(_ sender: NSDraggingInfo) -> CGPoint {
        convert(sender.draggingLocation, from: nil)
    }

    /// The app bundle behind a dragging item. `Bundle` instances are cached per path, and the
    /// hover's pasteboard inspection already made these.
    private func applicationID(_ item: NSDraggingItem) -> String? {
        guard let url = (item.item as? NSURL) as URL?, url.isFileURL,
              StripFileDropDelegate.DragPasteboardInspector.isApplication(url) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    /// Each app item's image becomes its drawer cell, the pointer keeping its place on the icon;
    /// later apps sit 4pt down-right, a small pile. Plain files keep the source's image.
    private func swapInCellImages(_ sender: NSDraggingInfo) {
        guard let dragImage else { return }
        let point = pointer(sender)
        let scale = window?.backingScaleFactor ?? 2
        var pile: CGFloat = 0
        sender.enumerateDraggingItems(options: [], for: self, classes: [NSURL.self], searchOptions: [:]) { item, index, _ in
            guard let id = self.applicationID(item), let cell = dragImage(id) else { return }
            // The source geometry is kept from the first swap: after a restore the item shows it again.
            let frame = item.draggingFrame
            var saved = self.swappedItems[index] ?? SwappedItem(
                components: item.imageComponents ?? [], size: frame.size,
                offset: CGVector(dx: frame.minX - point.x, dy: frame.minY - point.y),
                cellOffset: .zero, cellSize: .zero)
            let source = CGRect(x: point.x + saved.offset.dx, y: point.y + saved.offset.dy,
                                width: saved.size.width, height: saved.size.height)
            let icon = saved.components.first { $0.key == .icon }?.frame
            let target = DrawerDragImageGeometry.frame(itemFrame: source, iconComponent: icon, pointer: point,
                                                       bitmapSize: cell.image.size, cellIconRect: cell.iconRect,
                                                       backingScale: scale)
                .offsetBy(dx: 4 * pile, dy: -4 * pile)
            pile += 1
            item.setDraggingFrame(target, contents: cell.image)
            saved.cellOffset = CGVector(dx: target.minX - point.x, dy: target.minY - point.y)
            saved.cellSize = target.size
            self.swappedItems[index] = saved
        }
        showsCells = !swappedItems.isEmpty
    }

    /// The source's own images back, where they would be under the pointer now.
    private func restoreSourceImages(_ sender: NSDraggingInfo) {
        let point = pointer(sender)
        sender.enumerateDraggingItems(options: [], for: self, classes: [NSURL.self], searchOptions: [:]) { item, index, _ in
            guard let saved = self.swappedItems[index] else { return }
            let components = saved.components
            item.draggingFrame = CGRect(x: point.x + saved.offset.dx, y: point.y + saved.offset.dy,
                                        width: saved.size.width, height: saved.size.height)
            item.imageComponentsProvider = { components }
        }
        showsCells = false
    }

    /// The first app item's image at release, in screen coordinates: the cell frame this session
    /// asked for (the drawer), or the source image's icon (the capsule, which never swaps).
    private func dropLanding(_ sender: NSDraggingInfo) -> DrawerDropLanding? {
        let point = pointer(sender)
        var result: (String, CGRect)?
        sender.enumerateDraggingItems(options: [], for: self, classes: [NSURL.self], searchOptions: [:]) { item, index, stop in
            guard let id = self.applicationID(item) else { return }
            stop.pointee = true
            if self.showsCells, let saved = self.swappedItems[index] {
                result = (id, CGRect(x: point.x + saved.cellOffset.dx, y: point.y + saved.cellOffset.dy,
                                     width: saved.cellSize.width, height: saved.cellSize.height))
            } else if self.dragImage == nil {
                let frame = item.draggingFrame
                let icon = (item.imageComponents ?? []).first { $0.key == .icon }?.frame
                result = (id, icon.map { $0.offsetBy(dx: frame.minX, dy: frame.minY) } ?? frame)
            }
        }
        guard let (id, rect) = result, let window else { return nil }
        return DrawerDropLanding(bundleID: id, screenFrame: window.convertToScreen(convert(rect, to: nil)))
    }

    private func setTargeted(_ targeted: Bool, reportsLocation: Bool) {
        guard targeted != isTargeted else { return }
        isTargeted = targeted
        onHoverChange(targeted)
        if !targeted, reportsLocation { onHoverLocation(nil) }
    }

    private func armWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: Self.watchdogInterval, repeats: false) { [weak self] fired in
            DispatchQueue.main.async {
                // A newer update may have re-armed it between the fire and this turn.
                guard let self, self.watchdog === fired else { return }
                self.endSession()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }
}
