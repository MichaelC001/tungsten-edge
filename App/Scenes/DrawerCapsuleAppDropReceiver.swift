import AppKit
import SwiftUI

/// Takes app bundles dragged from outside (Finder) onto the drawer capsule. Plain AppKit rather
/// than SwiftUI `.onDrop`: the capsule is one target with no coordinate space to share, and only
/// AppKit can answer `.generic` (no "+" badge, as for an app dragged onto the strip).
///
/// Sized by its parent to the visible capsule + `DrawerAppDrop.capsuleTolerance`, so its bounds
/// are the drop zone.
struct DrawerCapsuleAppDropReceiver: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void
    let onDropApplications: ([URL]) -> Void

    func makeNSView(context: Context) -> DrawerCapsuleAppDropView { DrawerCapsuleAppDropView() }

    func updateNSView(_ view: DrawerCapsuleAppDropView, context: Context) {
        view.onHoverChange = onHoverChange
        view.onDropApplications = onDropApplications
    }

    static func dismantleNSView(_ view: DrawerCapsuleAppDropView, coordinator: ()) { view.endSession() }
}

final class DrawerCapsuleAppDropView: NSView {
    var onHoverChange: (Bool) -> Void = { _ in }
    var onDropApplications: ([URL]) -> Void = { _ in }

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

    /// Drags only; clicks, right clicks and scrolling go to the capsule's cells and receivers.
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
        endSession()
    }

    /// Off on an accepted drop: the drag image vanishes on release instead of hanging over the
    /// capsule while the app appears in its first cell.
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isSessionLive, isTargeted else { return false }
        sender.animatesToDestination = false
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let accepted = isSessionLive && isTargeted
        endSession()
        guard accepted else { return false }
        let dragged = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        // Trash items are dropped before the app check, as on the strip; plain files are not ours.
        let applications = dragged
            .filter { $0.isFileURL && !StripFileDropDelegate.DragPasteboardInspector.isInsideTrash($0) }
            .filter(StripFileDropDelegate.DragPasteboardInspector.isApplication)
        guard !applications.isEmpty else { return false }
        onDropApplications(applications)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        endSession()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        endSession()
    }

    func endSession() {
        isSessionLive = false
        watchdog?.invalidate()
        watchdog = nil
        setTargeted(false)
    }

    private func evaluate(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let accepts = DrawerAppDrop.accepts(
            containsApplication: StripFileDropDelegate.DragPasteboardInspector.containsApplication(),
            point: point,
            zone: bounds
        )
        setTargeted(accepts)
        armWatchdog()
        guard accepts else { return [] }
        return sender.draggingSourceOperationMask.contains(.generic) ? .generic : .copy
    }

    private func setTargeted(_ targeted: Bool) {
        guard targeted != isTargeted else { return }
        isTargeted = targeted
        onHoverChange(targeted)
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
