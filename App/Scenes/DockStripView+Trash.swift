import SwiftUI

extension DockStripView {
    func trashChip(hovered: Bool) -> some View {
        TrashChip(isFull: trashStore.isFull,
                  isDropTargeted: externalDropTarget == .trash,
                  scale: dockScale,
                  hoverStyle: hoverStyle,
                  isHovered: hovered,
                  menuItems: TrashMenuPlan.items(status: trashStore.status, isEmptying: trashStore.isEmptying),
                  onTap: { trashChipTapped() },
                  onOpen: { TrashStateStore.openTrashWindow(runtime: runtime, store: trashStore) },
                  onEmpty: { trashStore.emptyTrash() })
    }

    /// A click opens Finder's Trash window, as the native Dock does: open or bring forward only,
    /// never put it away — minimizing, closing or hiding a Finder window each raised another Finder
    /// window, flew toward the system Dock or flashed.
    func trashChipTapped() {
        TrashStateStore.openTrashWindow(runtime: runtime, store: trashStore)
        trashStore.askPermissionIfUndetermined()
    }
}
