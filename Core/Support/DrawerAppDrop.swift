import CoreGraphics

/// Dropping app bundles from outside (Finder) onto the drawer capsule: where it lands and how the
/// drawer order changes. The receiver is `DrawerCapsuleAppDropReceiver`; the commit is
/// `PanelCoordinator.stashDroppedApplications`.
enum DrawerAppDrop {
    /// The capsule's drop zone reaches this far past its visible content, the same as the
    /// strip→capsule stash zone (`PanelCoordinator.dragDropZones`), so both drags agree on the
    /// gap between bar and capsule (also 8pt) belonging to the capsule.
    static let capsuleTolerance: CGFloat = 8

    /// Whether a hover may light the capsule and a release may land: at least one app bundle that
    /// is not inside a Trash, with the point inside `zone` (visible capsule + tolerance).
    static func accepts(containsApplication: Bool, point: CGPoint, zone: CGRect) -> Bool {
        containsApplication && zone.contains(point)
    }

    /// The drawer order after a drop: the dropped ids first in drag order (deduped), everything
    /// else in its existing order. Ids not yet in `existing` are new members and go first too.
    static func frontOrder(existing: [String], dropped: [String]) -> [String] {
        var seen = Set<String>()
        let front = dropped.filter { !$0.isEmpty && seen.insert($0).inserted }
        return front + existing.filter { !seen.contains($0) }
    }
}
