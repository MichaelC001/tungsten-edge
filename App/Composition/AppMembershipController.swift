import Foundation

/// Single mutation boundary for app membership conversions.
///
/// Drawer membership is placement; kept membership means an entry survives app
/// exit. Kept, drawer, and messaging identity may all coexist; only Finder is
/// excluded from every membership.
@MainActor
final class AppMembershipController: ObservableObject {
    private let keptAppStore: KeptAppStore
    private let drawerStore: DrawerStore
    private let messagingStore: MessagingAppStore

    init(
        keptAppStore: KeptAppStore,
        drawerStore: DrawerStore,
        messagingStore: MessagingAppStore
    ) {
        self.keptAppStore = keptAppStore
        self.drawerStore = drawerStore
        self.messagingStore = messagingStore
    }

    /// Native check-menu toggle. It never changes placement. Kept may coexist with
    /// messaging identity under the unified model.
    func setKept(_ bundleID: String, enabled: Bool) {
        guard keptAppStore.canKeep(bundleID) else { return }
        if enabled {
            keptAppStore.add(bundleID)
        } else {
            keptAppStore.remove(bundleID)
        }
    }

    /// Placement-only move: this API never touches kept.
    ///
    /// Auto-enabling kept on stash is a **drag-landing** policy, not a placement-API one —
    /// it lives in `DragController.endDrag()` via `DragConversionPlan.enablesKeptOnDrop`.
    /// So do not restate it here, and note this method has no production caller today
    /// (menus offer no drawer placement action; drag is the only way in).
    func moveToDrawer(_ bundleID: String) {
        guard canChangeMembership(bundleID) else { return }
        drawerStore.add(bundleID)
    }

    /// 「标记为消息应用」：mark + 首次加入补 kept（默认保留）。不改 drawer——位置只能拖动改。
    func markMessaging(_ bundleID: String) {
        guard canChangeMembership(bundleID) else { return }
        if messagingStore.mark(bundleID) {
            keptAppStore.add(bundleID)
        }
    }

    /// Auto-tier registration: seed kept for each newly auto-detected messaging app
    /// (first registration only, so a later user un-check is not reopened). Does not
    /// change drawer placement.
    func autoRegisterMessaging(runningBundleIDs: Set<String>,
                               mainWindowIdentifiableBundleIDs: Set<String>) {
        let added = messagingStore.autoRegister(
            runningBundleIDs: runningBundleIDs,
            mainWindowIdentifiableBundleIDs: mainWindowIdentifiableBundleIDs
        )
        for bundleID in added {
            keptAppStore.add(bundleID)
        }
    }

    /// 取消「标记为消息应用」勾选：只清消息身份 + 记 opt-out；kept 与 drawer 保持不变。
    func unmarkMessaging(_ bundleID: String) {
        messagingStore.unmark(bundleID)
    }

    /// Startup repair. Only Finder's illegal memberships are cleared — Finder keeps
    /// its dedicated slot and must never sit in drawer/messaging. Kept and messaging
    /// deliberately coexist now, so there is no kept/messaging reconciliation.
    func reconcileInvalidMemberships() {
        let finder = KeptAppStore.forbiddenBundleID
        if drawerStore.contains(finder) {
            drawerStore.remove(finder)
        }
        if messagingStore.contains(finder) {
            messagingStore.unmark(finder)
        }
    }

    private func canChangeMembership(_ bundleID: String) -> Bool {
        !bundleID.isEmpty && bundleID != KeptAppStore.forbiddenBundleID
    }
}

/// Defensive, side-effect-free projections used by the strip, drawer, and capsule.
enum AppMembershipProjection {
    /// Full placement list. Hidden members remain here so their drawer order is
    /// stable when a later launch makes them visible again.
    static func drawerMembers(drawerIDs: [String]) -> [String] {
        filteredUnique(drawerIDs, excluding: [])
    }

    /// Core drawer visibility rule: placement is durable, but a chip is rendered
    /// only while the app runs or kept keeps it reachable. Messaging identity is no
    /// longer an independent retention condition — kept alone decides.
    static func visibleDrawerIDs(
        drawerIDs: [String],
        keptIDs: [String],
        runningIDs: Set<String>
    ) -> [String] {
        let retained = Set(keptIDs).union(runningIDs)
        return filteredUnique(drawerIDs, excluding: []).filter { retained.contains($0) }
    }

    /// Messaging-zone visibility: a messaging app not stashed in the drawer, shown
    /// only while running or kept. Order-preserving, deduped.
    static func visibleMessagingIDs(
        messagingIDs: [String],
        drawerIDs: [String],
        keptIDs: [String],
        runningIDs: Set<String>
    ) -> [String] {
        let retained = Set(keptIDs).union(runningIDs)
        return filteredUnique(messagingIDs, excluding: Set(drawerIDs)).filter { retained.contains($0) }
    }

    static func drawerPreview(
        drawerIDs: [String],
        keptIDs: [String],
        runningIDs: Set<String>,
        limit: Int = 9
    ) -> [String] {
        Array(visibleDrawerIDs(
            drawerIDs: drawerIDs,
            keptIDs: keptIDs,
            runningIDs: runningIDs
        ).prefix(max(0, limit)))
    }

    private static func filteredUnique(_ bundleIDs: [String], excluding excluded: Set<String>) -> [String] {
        var seen = Set<String>()
        return bundleIDs.filter { bundleID in
            !bundleID.isEmpty && !excluded.contains(bundleID) && seen.insert(bundleID).inserted
        }
    }
}
