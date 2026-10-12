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
    /// The accepted bundles and the release point in screen coordinates.
    let onDropApplications: ([URL], CGPoint) -> Void

    func makeNSView(context: Context) -> DrawerAppDropView { DrawerAppDropView() }

    func updateNSView(_ view: DrawerAppDropView, context: Context) {
        view.screenZone = screenZone
        view.onHoverChange = onHoverChange
        view.onDropApplications = onDropApplications
    }

    static func dismantleNSView(_ view: DrawerAppDropView, coordinator: ()) { view.endSession() }
}

final class DrawerAppDropView: NSView {
    var screenZone: (() -> CGRect)?
    var onHoverChange: (Bool) -> Void = { _ in }
    var onDropApplications: ([URL], CGPoint) -> Void = { _, _ in }

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
        // The exit report goes out before the landing: the spring-load's `.dropped` must be the
        // last word, so the drawer stays open on the app it just took.
        endSession()
        guard accepted else { return false }
        let dragged = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        // Trash items are dropped before the app check, as on the strip; plain files are not ours.
        let applications = dragged
            .filter { $0.isFileURL && !StripFileDropDelegate.DragPasteboardInspector.isInsideTrash($0) }
            .filter(StripFileDropDelegate.DragPasteboardInspector.isApplication)
        guard !applications.isEmpty else { return false }
        onDropApplications(applications, point)
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
