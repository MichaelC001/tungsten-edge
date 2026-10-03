import XCTest

/// 外部文件拖入任务条的几何路由纯函数（StripDropRouting.route）。
/// 布局假定："strip" 空间,中转格在 x=100..144,文件夹 chip 52pt 宽、8pt 间距从 x=152 起排。
final class StripDropRoutingTests: XCTestCase {
    func testTrashRoutingAndApplicationPriority() {
        let trash = CGRect(x: 320, y: 0, width: 40, height: 54)
        for shelf: CGRect? in [nil, .zero, CGRect(x: 0, y: 0, width: 40, height: 54)] {
            for x: CGFloat in [320, 340, 360, 380] {
                XCTAssertEqual(StripDropRouting.route(location: CGPoint(x: x, y: 20), isApplicationDrag: false, isTrashItemDrag: false,
                    shelfFrame: shelf, trashFrame: trash, folderFrames: [:], orderedPaths: []), .trash)
                XCTAssertEqual(StripDropRouting.route(location: CGPoint(x: x, y: 20), isApplicationDrag: true, isTrashItemDrag: false,
                    shelfFrame: shelf, trashFrame: trash, folderFrames: [:], orderedPaths: []), .keepApp)
            }
        }
        for frame: CGRect? in [nil, .zero] {
            XCTAssertEqual(StripDropRouting.route(location: CGPoint(x: 350, y: 20), isApplicationDrag: false, isTrashItemDrag: false,
                shelfFrame: nil, trashFrame: frame, folderFrames: [:], orderedPaths: []), .none)
        }
    }
    private let shelf = CGRect(x: 100, y: 0, width: 44, height: 52)

    private func frames(_ paths: [String], startX: CGFloat = 152) -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        var x = startX
        for path in paths {
            result["folder-" + path] = CGRect(x: x, y: 0, width: 52, height: 52)
            x += 60
        }
        return result
    }

    func testHitShelfStashes() {
        let target = StripDropRouting.route(location: CGPoint(x: 120, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: shelf, trashFrame: nil, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .stash)
    }

    func testLeftOfShelfIsNone() {
        let target = StripDropRouting.route(location: CGPoint(x: 50, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: shelf, trashFrame: nil, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .none)
    }

    func testZeroShelfFrameRejectsEverything() {
        let target = StripDropRouting.route(location: CGPoint(x: 120, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: .zero, trashFrame: nil, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .none)
    }

    func testNoFoldersPinsAtZeroWithinTailSlack() {
        // 中转格右缘 144 + 24pt 余量内 → 首次固定,插 0 位。
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: shelf, trashFrame: nil, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .pin(insertIndex: 0))
    }

    func testDropOnLeftHalfOfFirstFolderMovesIntoIt() {
        let paths = ["/a", "/b"]
        // 第一个 chip 在 152..204；左右半都属于移入目标。
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: shelf, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .moveInto(path: "/a"))
    }

    func testDropOnRightHalfOfFirstFolderMovesIntoIt() {
        let paths = ["/a", "/b"]
        let target = StripDropRouting.route(location: CGPoint(x: 190, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: shelf, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .moveInto(path: "/a"))
    }

    func testDropUsesHorizontalChipBand() {
        let paths = ["/a"]
        let target = StripDropRouting.route(location: CGPoint(x: 180, y: 200),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: shelf, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .moveInto(path: "/a"))
    }

    func testGapBetweenFoldersStillPins() {
        let paths = ["/a", "/b"]
        // 第一张右缘 204、第二张左缘 212；x=208 是真实 8pt 间隙。
        let target = StripDropRouting.route(location: CGPoint(x: 208, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: shelf, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 1))
    }

    func testMissingFrameDoesNotBecomeMoveTarget() {
        let paths = ["/a", "/b"]
        let partial = ["folder-/b": CGRect(x: 212, y: 0, width: 52, height: 52)]
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: shelf, trashFrame: nil, folderFrames: partial, orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 0))
    }

    func testTailSlackAfterLastFolderPinsAtEnd() {
        let paths = ["/a", "/b"]
        // 第二 chip 右缘 264,+24 余量内 → 追加末位(2)。
        let target = StripDropRouting.route(location: CGPoint(x: 276, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: shelf, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 2))
    }

    func testFarRightIsNone() {
        let paths = ["/a", "/b"]
        let target = StripDropRouting.route(location: CGPoint(x: 400, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: shelf, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .none)
    }

    // MARK: - 中转格关掉（shelfFrame = nil）

    func testHiddenShelfStillMovesIntoFolders() {
        let paths = ["/a", "/b"]
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: nil, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .moveInto(path: "/a"))
    }

    func testHiddenShelfKeepsHeadSlackForInsertAtZero() {
        let paths = ["/a", "/b"]
        // 首个 chip 左缘 152，headSlack 8 → 144..152 是「插到最前面」的唯一落点。
        // 没有这段的话首个 chip 整段先被判成 moveInto，插 0 位就永远做不到了。
        let target = StripDropRouting.route(location: CGPoint(x: 147, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: nil, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 0))
    }

    func testHiddenShelfRejectsLeftOfHeadSlack() {
        let paths = ["/a"]
        let target = StripDropRouting.route(location: CGPoint(x: 120, y: 26),
                                            isApplicationDrag: false, isTrashItemDrag: false,
                                            shelfFrame: nil, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .none, "中转格关掉后，它原来的位置不能再接收任何拖放")
    }

    func testHiddenShelfStillPinsInGapAndTailSlack() {
        let paths = ["/a", "/b"]
        XCTAssertEqual(
            StripDropRouting.route(location: CGPoint(x: 208, y: 26),
                                   isApplicationDrag: false, isTrashItemDrag: false,
                                   shelfFrame: nil, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths),
            .pin(insertIndex: 1)
        )
        XCTAssertEqual(
            StripDropRouting.route(location: CGPoint(x: 276, y: 26),
                                   isApplicationDrag: false, isTrashItemDrag: false,
                                   shelfFrame: nil, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths),
            .pin(insertIndex: 2)
        )
    }

    func testHiddenShelfWithNoFoldersRejectsEverything() {
        // 中转格关掉 + 一个固定文件夹都没有 → 文件夹区整体不存在，任务条上没有任何落点。
        // 这是已接受的边界：回路是菜单里把「显示中转站」勾回来。
        for x in [CGFloat(50), 120, 160, 400] {
            XCTAssertEqual(
                StripDropRouting.route(location: CGPoint(x: x, y: 26),
                                       isApplicationDrag: false, isTrashItemDrag: false,
                                       shelfFrame: nil, trashFrame: nil, folderFrames: [:], orderedPaths: []),
                .none
            )
        }
    }

    // MARK: - 拖的是应用（安全边界）

    /// **本文件最要紧的一条**：应用永远只会得到 `.keepApp`。
    /// `.moveInto` 是真实的文件移动（同卷移动、跨卷复制）——漏一个应用进去就等于把它从
    /// 「应用程序」里搬走；`.pin` 会把它固定成一个展开 `.app` 内部结构的文件夹格子
    /// （2026-09-07 之前的真实 bug，`.app` 本身就是目录，`isDirectoryKey` 判不出来）。
    func testApplicationDragNeverReachesAnyFileTarget() {
        let paths = ["/a", "/b"]
        let folders = frames(paths)
        // 中转格上、首个文件夹格子上、格子之间的缝、尾部余量、条外、条最左端 —— 全覆盖。
        for x in [CGFloat(0), 50, 120, 147, 160, 190, 208, 276, 400, 2000] {
            for shelfFrame in [shelf, nil] {
                let target = StripDropRouting.route(location: CGPoint(x: x, y: 26),
                                                    isApplicationDrag: true, isTrashItemDrag: false,
                                                    shelfFrame: shelfFrame, trashFrame: nil,
                                                    folderFrames: folders, orderedPaths: paths)
                XCTAssertEqual(target, .keepApp, "x=\(x) shelf=\(String(describing: shelfFrame))")
            }
        }
    }

    /// 中转格关掉 + 一个固定文件夹都没有 = 文件那条路整条都没有落点（已接受的边界），
    /// 但应用照样能落——这正是本次要补上的入口。
    func testApplicationDragLandsEvenWithNoFileDropTargetAtAll() {
        for x in [CGFloat(50), 120, 160, 400] {
            XCTAssertEqual(
                StripDropRouting.route(location: CGPoint(x: x, y: 26),
                                       isApplicationDrag: true, isTrashItemDrag: false,
                                       shelfFrame: nil, trashFrame: nil,
                                       folderFrames: [:], orderedPaths: []),
                .keepApp
            )
        }
    }

    /// 反向锁：不是应用的时候，`.keepApp` 绝不会冒出来（否则普通文件也会去勾保留）。
    func testNonApplicationDragNeverKeepsAnApp() {
        let paths = ["/a", "/b"]
        for x in [CGFloat(0), 50, 120, 147, 160, 208, 276, 400] {
            XCTAssertNotEqual(
                StripDropRouting.route(location: CGPoint(x: x, y: 26),
                                       isApplicationDrag: false, isTrashItemDrag: false,
                                       shelfFrame: shelf, trashFrame: nil,
                                       folderFrames: frames(paths), orderedPaths: paths),
                .keepApp
            )
        }
    }

    // MARK: - 让位空档

    func testGhostInsertsBeforeOrAfterTheAnchor() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(StripDropRouting.ghostInsertionIndex(orderedIDs: ids, targetID: "a", after: false), 0)
        XCTAssertEqual(StripDropRouting.ghostInsertionIndex(orderedIDs: ids, targetID: "a", after: true), 1)
        XCTAssertEqual(StripDropRouting.ghostInsertionIndex(orderedIDs: ids, targetID: "c", after: true), 3)
    }

    /// 锚点是上一帧算的，这一帧那张卡可能已经不在了（应用退出 / 换屏过滤）。
    /// 必须落末尾，绝不能返回越界下标——投影层拿它直接 `insert(at:)`。
    func testGhostFallsToTailWhenAnchorIsGone() {
        let ids = ["a", "b"]
        XCTAssertEqual(StripDropRouting.ghostInsertionIndex(orderedIDs: ids, targetID: "gone", after: false), 2)
        XCTAssertEqual(StripDropRouting.ghostInsertionIndex(orderedIDs: ids, targetID: nil, after: true), 2)
        XCTAssertEqual(StripDropRouting.ghostInsertionIndex(orderedIDs: [], targetID: "a", after: true), 0)
    }

    /// **门控的命门**：指针停在空档里时，左右两张卡等距，判定会在「左邻的右边」和
    /// 「右邻的左边」之间摇摆——两者指的是同一个空位。折成序号必须归一，否则每摇摆一次
    /// 就是一趟「位置没变却重算整条任务条」。
    func testEquivalentAnchorsCollapseToTheSameSlot() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(
            StripDropRouting.ghostInsertionIndex(orderedIDs: ids, targetID: "a", after: true),
            StripDropRouting.ghostInsertionIndex(orderedIDs: ids, targetID: "b", after: false)
        )
        XCTAssertEqual(
            StripDropRouting.ghostInsertionIndex(orderedIDs: ids, targetID: "b", after: true),
            StripDropRouting.ghostInsertionIndex(orderedIDs: ids, targetID: "c", after: false)
        )
    }

    /// 变化门控的判据。同一个空位重复喂必须判为「没变」。
    func testGhostEqualityGatesRedraws() {
        let a = StripDropGhost(zone: .live(bundleID: "com.foo"), insertIndex: 2)
        XCTAssertEqual(a, StripDropGhost(zone: .live(bundleID: "com.foo"), insertIndex: 2))
        XCTAssertNotEqual(a, StripDropGhost(zone: .live(bundleID: "com.foo"), insertIndex: 3))
        XCTAssertNotEqual(a, StripDropGhost(zone: .live(bundleID: "com.other"), insertIndex: 2))
        XCTAssertNotEqual(a, StripDropGhost(zone: .folder, insertIndex: 2))
    }

    // MARK: - Folder dragged in: pin edges and the make-way gap

    private let edge = StripDropRouting.folderPinEdgeFraction

    /// 52pt chips → 13pt pin edges. /a is 152..204, /b is 212..264.
    func testFolderDragPinsFromTheChipEdgesAndMovesIntoTheCentre() {
        let paths = ["/a", "/b"]
        let expected: [(CGFloat, StripDropRouting.Target)] = [
            (160, .pin(insertIndex: 0)), (178, .moveInto(path: "/a")), (198, .pin(insertIndex: 1)),
            (208, .pin(insertIndex: 1)), (216, .pin(insertIndex: 1)), (238, .moveInto(path: "/b")),
            (258, .pin(insertIndex: 2)), (276, .pin(insertIndex: 2)),
        ]
        for (x, target) in expected {
            XCTAssertEqual(
                StripDropRouting.route(location: CGPoint(x: x, y: 26),
                                       isApplicationDrag: false, isTrashItemDrag: false,
                                       shelfFrame: shelf, trashFrame: nil, folderFrames: frames(paths),
                                       orderedPaths: paths, pinEdgeFraction: edge),
                target, "x=\(x)")
        }
    }

    /// Lays the folders out with the gap already open at `gapIndex`, as the strip renders them
    /// (the gap reports no frame), and returns the gap's own extent.
    private func layout(_ paths: [String], gapIndex: Int, startX: CGFloat = 152)
        -> (frames: [String: CGRect], gap: ClosedRange<CGFloat>) {
        var result: [String: CGRect] = [:]
        var x = startX
        var gap: ClosedRange<CGFloat> = startX...startX
        for index in 0...paths.count {
            if index == gapIndex { gap = x...(x + 52); x += 60 }
            guard index < paths.count else { break }
            result["folder-" + paths[index]] = CGRect(x: x, y: 0, width: 52, height: 52)
            x += 60
        }
        return (result, gap)
    }

    /// **The stability lock**: once the gap is open, a pointer anywhere inside it (and across the
    /// spacing and pin edges on both sides) must keep resolving to that same slot — any other
    /// answer closes the gap, which moves the chips, which reopens it.
    func testPointerInsideTheOpenGapKeepsResolvingToTheSameSlot() {
        let paths = ["/a", "/b"]
        for shelfFrame in [shelf, nil] {
            for gapIndex in 0...paths.count {
                let (folders, gap) = layout(paths, gapIndex: gapIndex)
                let openGap = StripDropRouting.OpenFolderGap(insertIndex: gapIndex, width: 60)
                // 6pt each side: the 8pt spacing short of the neighbour's own edge (the shelf at 144).
                for x in stride(from: gap.lowerBound - 6, through: gap.upperBound + 6, by: 2) {
                    let target = StripDropRouting.route(
                        location: CGPoint(x: x, y: 26), isApplicationDrag: false, isTrashItemDrag: false,
                        shelfFrame: shelfFrame, trashFrame: nil, folderFrames: folders, orderedPaths: paths,
                        pinEdgeFraction: edge, openGap: openGap)
                    XCTAssertEqual(target, .pin(insertIndex: gapIndex),
                                   "gap=\(gapIndex) x=\(x) shelf=\(String(describing: shelfFrame))")
                }
            }
        }
    }

    func testFirstPinGapNextToTheShelfStaysOpen() {
        // No folders yet: the gap sits right of the shelf (144) and is wider than the 24pt tail slack.
        let openGap = StripDropRouting.OpenFolderGap(insertIndex: 0, width: 60)
        for x: CGFloat in [150, 170, 190, 204] {
            XCTAssertEqual(
                StripDropRouting.route(location: CGPoint(x: x, y: 26), isApplicationDrag: false, isTrashItemDrag: false,
                                       shelfFrame: shelf, trashFrame: nil, folderFrames: [:], orderedPaths: [],
                                       pinEdgeFraction: edge, openGap: openGap),
                .pin(insertIndex: 0), "x=\(x)")
        }
    }

    /// A plain file among the folders keeps the old routing for the whole drag: on a chip's edge
    /// the folders would pin and the file would be left behind.
    func testOnlyAFoldersOnlyDragPinsFolders() {
        XCTAssertTrue(StripDropRouting.dragPinsFolders(nonApplicationItemsAreDirectories: [true]))
        XCTAssertTrue(StripDropRouting.dragPinsFolders(nonApplicationItemsAreDirectories: [true, true]))
        XCTAssertFalse(StripDropRouting.dragPinsFolders(nonApplicationItemsAreDirectories: [true, false]))
        XCTAssertFalse(StripDropRouting.dragPinsFolders(nonApplicationItemsAreDirectories: [false]))
        XCTAssertFalse(StripDropRouting.dragPinsFolders(nonApplicationItemsAreDirectories: []))
    }

    func testFolderGhostFollowsPinSticksOverAChipAndClosesElsewhere() {
        XCTAssertEqual(StripDropRouting.folderGhostIndex(current: nil, target: .pin(insertIndex: 1), pinsFolder: true), 1)
        XCTAssertEqual(StripDropRouting.folderGhostIndex(current: 1, target: .pin(insertIndex: 2), pinsFolder: true), 2)
        // Over a chip's centre the gap stays put, and none opens if there was none.
        XCTAssertEqual(StripDropRouting.folderGhostIndex(current: 1, target: .moveInto(path: "/a"), pinsFolder: true), 1)
        XCTAssertNil(StripDropRouting.folderGhostIndex(current: nil, target: .moveInto(path: "/a"), pinsFolder: true))
        for target: StripDropRouting.Target in [.stash, .trash, .none, .keepApp] {
            XCTAssertNil(StripDropRouting.folderGhostIndex(current: 1, target: target, pinsFolder: true), "\(target)")
        }
        // A plain file never opens a gap: it cannot be pinned.
        XCTAssertNil(StripDropRouting.folderGhostIndex(current: nil, target: .pin(insertIndex: 1), pinsFolder: false))
    }

    func testHiddenShelfIgnoresStaleShelfCoordinates() {
        // 视图侧必须传 nil 而不是旧帧：这条锁住「传了 nil 就绝不会再命中 stash」。
        let paths = ["/a"]
        let onShelfSpot = CGPoint(x: 120, y: 26)
        XCTAssertEqual(
            StripDropRouting.route(location: onShelfSpot,
                                   isApplicationDrag: false, isTrashItemDrag: false,
                                   shelfFrame: shelf, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths),
            .stash
        )
        XCTAssertEqual(
            StripDropRouting.route(location: onShelfSpot,
                                   isApplicationDrag: false, isTrashItemDrag: false,
                                   shelfFrame: nil, trashFrame: nil, folderFrames: frames(paths), orderedPaths: paths),
            .none
        )
    }

    func testOnlyTheTrashAndAFolderPinSlotDropTheCursorBadge() {
        for pinsFolder in [true, false] {
            XCTAssertTrue(StripDropRouting.usesGenericOperation(hoveredTarget: .trash, pinsFolder: pinsFolder,
                                                                proposedIsCopy: true, sourceAllowsGeneric: true))
            let others: [StripDropRouting.Target?] = [nil, .none, .stash, .keepApp, .moveInto(path: "/tmp/a")]
            for target in others {
                XCTAssertFalse(StripDropRouting.usesGenericOperation(hoveredTarget: target, pinsFolder: pinsFolder,
                                                                     proposedIsCopy: true, sourceAllowsGeneric: true),
                               "\(String(describing: target))")
            }
        }
        XCTAssertTrue(StripDropRouting.usesGenericOperation(hoveredTarget: .pin(insertIndex: 0), pinsFolder: true,
                                                            proposedIsCopy: true, sourceAllowsGeneric: true))
        // A plain file over a chip gap pins nothing; its badge is left alone.
        XCTAssertFalse(StripDropRouting.usesGenericOperation(hoveredTarget: .pin(insertIndex: 0), pinsFolder: false,
                                                             proposedIsCopy: true, sourceAllowsGeneric: true))
    }

    func testBadgeAnswerIsKeptWhenGenericIsNotOffered() {
        for target: StripDropRouting.Target in [.trash, .pin(insertIndex: 0)] {
            // ⌥ held: the source offers copy only.
            XCTAssertFalse(StripDropRouting.usesGenericOperation(hoveredTarget: target, pinsFolder: true,
                                                                 proposedIsCopy: true, sourceAllowsGeneric: false))
            // A refusal (e.g. Trash items) stays a refusal.
            XCTAssertFalse(StripDropRouting.usesGenericOperation(hoveredTarget: target, pinsFolder: true,
                                                                 proposedIsCopy: false, sourceAllowsGeneric: true))
        }
    }

    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    private let appA = URL(fileURLWithPath: "/Applications/A.app")
    private let appB = URL(fileURLWithPath: "/Applications/B.app")
    private let file = URL(fileURLWithPath: "/Users/tester/Downloads/note.txt")

    func testProvidersStayTheAuthorityWheneverAnyOfThemLoads() {
        // All loaded: the pasteboard is ignored even when it disagrees.
        XCTAssertEqual(StripDropRouting.committedURLs(loaded: [appA, file], pasteboard: [appB], homeDirectory: home),
                       [appA, file])
        // Partly loaded: only what loaded, never topped up from the pasteboard.
        XCTAssertEqual(StripDropRouting.committedURLs(loaded: [nil, file], pasteboard: [appA, file], homeDirectory: home),
                       [file])
    }

    func testInProcessDragFallsBackToThePasteboard() {
        // Our popup's provider cannot coerce to URL: every load is nil.
        XCTAssertEqual(StripDropRouting.committedURLs(loaded: [nil], pasteboard: [appA], homeDirectory: home), [appA])
        XCTAssertEqual(StripDropRouting.committedURLs(loaded: [nil, nil], pasteboard: [], homeDirectory: home), [])
    }

    func testCommittedURLsDropTrashItemsFromEitherSource() {
        let homeTrash = URL(fileURLWithPath: "/Users/tester/.Trash/old.txt")
        let volumeTrash = URL(fileURLWithPath: "/.Trashes/501/old.app")
        XCTAssertEqual(StripDropRouting.committedURLs(loaded: [homeTrash, file, volumeTrash], pasteboard: [], homeDirectory: home),
                       [file])
        XCTAssertEqual(StripDropRouting.committedURLs(loaded: [nil], pasteboard: [homeTrash, appA, volumeTrash], homeDirectory: home),
                       [appA])
        // Loaded but all in the Trash: the selection is not retried against the pasteboard.
        XCTAssertEqual(StripDropRouting.committedURLs(loaded: [homeTrash], pasteboard: [appA], homeDirectory: home), [])
    }
}
