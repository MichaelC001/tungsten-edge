import CoreGraphics
import XCTest

final class PanelGeometryTests: XCTestCase {
    private let metrics = PanelLayoutMetrics.tungstenEdge

    func testBottomDockVisibleFrameChangeDoesNotMoveBottomPanelsVertically() {
        let hidden = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let shown = screen(
            frame: hidden.frame,
            visibleFrame: CGRect(x: 0, y: 80, width: 1512, height: 869)
        )

        let hiddenLayout = layout(on: hidden)
        let shownLayout = layout(on: shown)

        XCTAssertEqual(hiddenLayout.dock.minY, shownLayout.dock.minY)
        XCTAssertEqual(hiddenLayout.capsule.minY, shownLayout.capsule.minY)
        XCTAssertEqual(hiddenLayout.drawer.minY, shownLayout.drawer.minY)
    }

    func testSideDockVisibleFrameChangeDoesNotMoveOrResizeBottomPanelsHorizontally() {
        let hidden = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let leftDockShown = screen(
            frame: hidden.frame,
            visibleFrame: CGRect(x: 90, y: 0, width: 1422, height: 949)
        )
        let rightDockShown = screen(
            frame: hidden.frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1422, height: 949)
        )

        let hiddenLayout = layout(on: hidden)
        for candidate in [layout(on: leftDockShown), layout(on: rightDockShown)] {
            XCTAssertEqual(candidate.dock.minX, hiddenLayout.dock.minX)
            XCTAssertEqual(candidate.dock.width, hiddenLayout.dock.width)
            XCTAssertEqual(candidate.capsule.minX, hiddenLayout.capsule.minX)
            XCTAssertEqual(candidate.drawer.minX, hiddenLayout.drawer.minX)
        }
    }

    func testBottomAnchoringUsesNonZeroScreenMinY() {
        let upperScreen = screen(frame: CGRect(x: -488, y: 982, width: 2560, height: 1440))
        let lowerScreen = screen(frame: CGRect(x: -2408, y: -640, width: 1920, height: 1080))

        XCTAssertEqual(layout(on: upperScreen).dock.minY, upperScreen.frame.minY + metrics.bottomGap - metrics.shadowPadding)
        XCTAssertEqual(layout(on: lowerScreen).dock.minY, lowerScreen.frame.minY + metrics.bottomGap - metrics.shadowPadding)
    }

    func testDockFrameKeepsOriginalBottomCoordinate() {
        let screen = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))

        let dock = PanelGeometry.dockTargetFrame(contentWidth: 620, on: screen, metrics: metrics)

        XCTAssertEqual(dock.minY, -12, "bottomGap 8 − shadowPadding 20，与档位高度无关")
        XCTAssertEqual(dock.height, 94, "中档 54 + 2×20")
    }

    func testDrawerTopCapUsesVisibleFrameWhenMenuBarIsLowerThanSafeAreaCap() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 920),
            safeAreaTop: 32
        )
        XCTAssertEqual(screen.topUsableY, 920)

        let drawer = layout(on: screen, drawerSize: CGSize(width: 210, height: 900)).drawer

        XCTAssertEqual(drawer.maxY, 920)
    }

    func testDrawerTopCapUsesSafeAreaWhenNotchIsLowerThanVisibleFrame() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 32
        )
        XCTAssertEqual(screen.topUsableY, 950)

        let drawer = layout(on: screen, drawerSize: CGSize(width: 210, height: 900)).drawer

        XCTAssertEqual(drawer.maxY, 950)
    }

    func testMaxDrawerContentHeightUsesSameTopCapAsDrawerFrame() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 32
        )
        let frames = layout(on: screen)

        let maxHeight = PanelGeometry.maxDrawerContentHeight(forCapsule: frames.capsule, on: screen, metrics: metrics)

        XCTAssertEqual(maxHeight, (screen.topUsableY - frames.drawer.minY) - 2 * metrics.shadowPadding)
    }

    // MARK: - 文件夹弹窗

    func testFolderPopupAnchorsAboveAnchorRectAndCenters() {
        let screen = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let anchor = CGRect(x: 700, y: 8, width: 44, height: 52)

        let popup = PanelGeometry.folderPopupTargetFrame(
            anchorVisibleRect: anchor, size: CGSize(width: 400, height: 300), on: screen, metrics: metrics
        )
        let plate = PanelGeometry.folderPopupPlateFrame(panelFrame: popup)

        // The arrow's tip (bottom of the visible part) floats 3pt above the chip.
        XCTAssertEqual(plate.minY, anchor.maxY + StackPopupMetrics.tipGap)
        XCTAssertEqual(popup.midX, anchor.midX)
        XCTAssertEqual(popup.height, 300)
    }

    func testFolderPopupKeepsThePlateInsideTheScreenMargin() {
        let screen = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        // Near the edges, but far enough in that the margin does not have to give way.
        let leftAnchor = CGRect(x: 100, y: 8, width: 44, height: 52)
        let rightAnchor = CGRect(x: 1368, y: 8, width: 44, height: 52)
        let size = CGSize(width: 400, height: 300)

        let left = PanelGeometry.folderPopupTargetFrame(anchorVisibleRect: leftAnchor, size: size, on: screen, metrics: metrics)
        let right = PanelGeometry.folderPopupTargetFrame(anchorVisibleRect: rightAnchor, size: size, on: screen, metrics: metrics)

        // The window overhangs the screen by its transparent border; the plate never does.
        XCTAssertEqual(PanelGeometry.folderPopupPlateFrame(panelFrame: left).minX,
                       screen.frame.minX + StackPopupMetrics.screenMargin)
        XCTAssertEqual(PanelGeometry.folderPopupPlateFrame(panelFrame: right).maxX,
                       screen.frame.maxX - StackPopupMetrics.screenMargin)
    }

    /// Clamp and arrow together: wherever the chip is, the arrow's tip ends up on its centre —
    /// the plate gives up its screen margin before the arrow gives up the chip.
    func testFolderPopupArrowLandsOnTheAnchorCenter() {
        let screen = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let size = StackPopupMetrics.panelSize(forPlate: StackPopupMetrics.plateSize(columns: 7, rows: 4, hasNote: false))
        // Mid-screen, the nearest centre the arrow can still reach (minimum margin + arrow inset),
        // and the same on the right. Nearer than `reach` the arrow is off by `reach − distance`:
        // 7pt for the first chip of a full-width bar at the default height, 18pt at the smallest.
        let reach = StackPopupMetrics.minimumScreenMargin + StackPopupMetrics.arrowInset
        for center in [756, 200, 81, reach, 1512 - reach, 1431, 1300] as [CGFloat] {
            let anchor = CGRect(x: center - 20, y: 8, width: 40, height: 47)
            let popup = PanelGeometry.folderPopupTargetFrame(anchorVisibleRect: anchor, size: size, on: screen, metrics: metrics)
            let plate = PanelGeometry.folderPopupPlateFrame(panelFrame: popup)
            let arrow = StackPopupOutline.clampedArrowCenterX(plate.width / 2 + (anchor.midX - popup.midX), plateWidth: plate.width)
            XCTAssertEqual(plate.minX + arrow, anchor.midX, accuracy: 0.001, "anchor centre \(center)")
            XCTAssertGreaterThanOrEqual(plate.minX, screen.frame.minX + StackPopupMetrics.minimumScreenMargin)
            XCTAssertLessThanOrEqual(plate.maxX, screen.frame.maxX - StackPopupMetrics.minimumScreenMargin)
        }
        // Closer than that — whatever put the chip there: a full-width bar (39), one just short of
        // the width cap at the smallest height (33), the smallest bar at full width (28) — the
        // plate stops at the minimum margin and the arrow is off by exactly `reach − distance`.
        for distance in [39, 33, 28] as [CGFloat] {
            for center in [distance, 1512 - distance] {
                let anchor = CGRect(x: center - 12, y: 8, width: 24, height: 28)
                let popup = PanelGeometry.folderPopupTargetFrame(anchorVisibleRect: anchor, size: size, on: screen, metrics: metrics)
                let plate = PanelGeometry.folderPopupPlateFrame(panelFrame: popup)
                let arrow = StackPopupOutline.clampedArrowCenterX(plate.width / 2 + (anchor.midX - popup.midX), plateWidth: plate.width)
                XCTAssertEqual(abs(plate.minX + arrow - anchor.midX), reach - distance, accuracy: 0.001, "distance \(distance)")
                XCTAssertEqual(min(plate.minX, 1512 - plate.maxX), StackPopupMetrics.minimumScreenMargin, accuracy: 0.001)
            }
        }
    }

    func testFolderPopupHeightCappedByTopUsableY() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 920),
            safeAreaTop: 0
        )
        let anchor = CGRect(x: 700, y: 8, width: 44, height: 52)

        let popup = PanelGeometry.folderPopupTargetFrame(
            anchorVisibleRect: anchor, size: CGSize(width: 400, height: 2000), on: screen, metrics: metrics
        )

        XCTAssertEqual(PanelGeometry.folderPopupPlateFrame(panelFrame: popup).maxY, screen.topUsableY)
    }

    func testStackPopupRowsFitUnderTheMenuBar() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1352, height: 878),
            visibleFrame: CGRect(x: 0, y: 0, width: 1352, height: 845),
            safeAreaTop: 0
        )
        let anchor = CGRect(x: 700, y: 8, width: 44, height: 47)

        let available = PanelGeometry.stackPopupAvailablePlateHeight(anchorVisibleRect: anchor, on: screen)
        let limits = StackGridLayout.limits(screenSize: screen.frame.size, availablePlateHeight: available)
        XCTAssertEqual(limits, .init(maxColumns: 7, nominalRows: 4, fitRows: 5, fitRowsWithNote: 5))
        // The tallest plate those limits allow — with and without a status line — clears the menu bar.
        for (rows, hasNote) in [(limits.fitRows, false), (limits.fitRowsWithNote, true)] {
            let plate = StackPopupMetrics.plateSize(columns: limits.maxColumns, rows: rows, hasNote: hasNote)
            let popup = PanelGeometry.folderPopupTargetFrame(
                anchorVisibleRect: anchor, size: StackPopupMetrics.panelSize(forPlate: plate), on: screen, metrics: metrics
            )
            XCTAssertEqual(popup.height, StackPopupMetrics.panelSize(forPlate: plate).height)
            XCTAssertLessThanOrEqual(PanelGeometry.folderPopupPlateFrame(panelFrame: popup).maxY,
                                     screen.topUsableY - PanelGeometry.stackPopupTopGap)
        }
    }

    /// The switch tween feeds the clamp an interpolated centre and interpolated margins. Its first
    /// tick must reproduce the frame on screen and its last the target — also when the popup it
    /// starts from hugs the screen edge with a margin that gave way.
    func testFolderPopupSwitchTweenStartsOnTheCurrentFrameAndEndsOnTheTarget() {
        let screen = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let size = StackPopupMetrics.panelSize(forPlate: StackPopupMetrics.plateSize(columns: 3, rows: 1, hasNote: false))
        func tick(from start: CGRect, to anchor: CGRect, progress p: CGFloat) -> CGPoint {
            let startMargins = PanelGeometry.folderPopupScreenMargins(holding: start, on: screen)
            let endMargins = PanelGeometry.folderPopupScreenMargins(anchorCenterX: anchor.midX, on: screen)
            let endBottom = PanelGeometry.folderPopupDesiredBottomY(anchorVisibleRect: anchor)
            return PanelGeometry.folderPopupClampedOrigin(
                desiredCenterX: start.midX + (anchor.midX - start.midX) * p,
                desiredBottomY: start.minY + (endBottom - start.minY) * p,
                size: size, margins: startMargins.interpolated(to: endMargins, progress: p), on: screen)
        }
        // Edge chip → its neighbour, neighbour → mid-screen, mid-screen → the far edge, and a
        // re-switch from a frame caught mid-flight.
        let anchors = [39, 81, 700, 1484].map { CGRect(x: CGFloat($0) - 20, y: 8, width: 40, height: 47) }
        var starts = anchors.map { PanelGeometry.folderPopupTargetFrame(anchorVisibleRect: $0, size: size, on: screen, metrics: metrics) }
        starts.append(CGRect(origin: tick(from: starts[0], to: anchors[2], progress: 0.4), size: size))
        for start in starts {
            for anchor in anchors {
                let target = PanelGeometry.folderPopupTargetFrame(anchorVisibleRect: anchor, size: size, on: screen, metrics: metrics)
                let first = tick(from: start, to: anchor, progress: 0)
                let last = tick(from: start, to: anchor, progress: 1)
                XCTAssertEqual(first.x, start.minX, accuracy: 0.001)
                XCTAssertEqual(first.y, start.minY, accuracy: 0.001)
                XCTAssertEqual(last.x, target.minX, accuracy: 0.001)
                XCTAssertEqual(last.y, target.minY, accuracy: 0.001)
            }
        }
    }

    // MARK: - Window title tooltip

    func testWindowTitleTooltipAnchorsVisibleBubbleAbovePillAndCenters() {
        let screen = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let anchor = CGRect(x: 700, y: 20, width: 160, height: 34)
        let frame = PanelGeometry.windowTitleTooltipTargetFrame(
            anchorVisibleRect: anchor, size: CGSize(width: 300, height: 60),
            tipGap: WindowTitleTooltipStyle.native.tipGap, on: screen
        )
        let bubble = frame.insetBy(dx: PanelGeometry.windowTitleTooltipShadowPadding,
                                   dy: PanelGeometry.windowTitleTooltipShadowPadding)

        XCTAssertEqual(bubble.minY, anchor.maxY + WindowTitleTooltipStyle.native.tipGap)
        XCTAssertEqual(bubble.midX, anchor.midX)
    }

    func testWindowTitleTooltipClampsVisibleBubbleInsideNonZeroScreenEdges() {
        let screen = screen(frame: CGRect(x: -1512, y: 982, width: 1512, height: 982))
        let size = CGSize(width: 300, height: 60)
        let left = PanelGeometry.windowTitleTooltipTargetFrame(
            anchorVisibleRect: CGRect(x: screen.frame.minX, y: 1000, width: 40, height: 30),
            size: size, tipGap: WindowTitleTooltipStyle.native.tipGap, on: screen
        ).insetBy(dx: PanelGeometry.windowTitleTooltipShadowPadding,
                  dy: PanelGeometry.windowTitleTooltipShadowPadding)
        let right = PanelGeometry.windowTitleTooltipTargetFrame(
            anchorVisibleRect: CGRect(x: screen.frame.maxX - 40, y: 1000, width: 40, height: 30),
            size: size, tipGap: WindowTitleTooltipStyle.native.tipGap, on: screen
        ).insetBy(dx: PanelGeometry.windowTitleTooltipShadowPadding,
                  dy: PanelGeometry.windowTitleTooltipShadowPadding)

        XCTAssertEqual(left.minX, screen.frame.minX + PanelGeometry.windowTitleTooltipScreenMargin)
        XCTAssertEqual(right.maxX, screen.frame.maxX - PanelGeometry.windowTitleTooltipScreenMargin)
    }

    func testWindowTitleTooltipRespectsTopUsableY() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 920),
            safeAreaTop: 0
        )
        let frame = PanelGeometry.windowTitleTooltipTargetFrame(
            anchorVisibleRect: CGRect(x: 700, y: 900, width: 100, height: 30),
            size: CGSize(width: 300, height: 60),
            tipGap: WindowTitleTooltipStyle.native.tipGap, on: screen
        )
        let bubble = frame.insetBy(dx: PanelGeometry.windowTitleTooltipShadowPadding,
                                   dy: PanelGeometry.windowTitleTooltipShadowPadding)

        XCTAssertEqual(bubble.maxY, screen.topUsableY)
    }

    // MARK: - 条高（连续）

    private let sampleHeights: [DockPanelHeight] = [32, 40, 47, 54, 63, 80, 120].map { DockPanelHeight(clamping: $0) }

    func testClampingRoundsAndClampsToTheRange() {
        XCTAssertEqual(DockPanelHeight(clamping: 31.4).points, 32)
        XCTAssertEqual(DockPanelHeight(clamping: 40.6).points, 41)
        XCTAssertEqual(DockPanelHeight(clamping: 120.4).points, 120)
        XCTAssertEqual(DockPanelHeight(clamping: 200).points, 120)
        XCTAssertEqual(DockPanelHeight(clamping: 0).points, 32)
        XCTAssertEqual(DockPanelHeight(clamping: .nan).points, 54)
        XCTAssertEqual(DockPanelHeight(clamping: .infinity).points, 54)
        // 32…120 mirrors the reach of the Dock's own Size slider; both ends stay reachable by
        // the settings slider and the grip, and every legacy tier value lands strictly inside.
        XCTAssertEqual(DockPanelHeight.minimum, 32)
        XCTAssertEqual(DockPanelHeight.maximum, 120)
    }

    func testLegacyTierMigrationTable() {
        // The four raw strings are the frozen contract of the tier releases' UserDefaults key.
        XCTAssertEqual(DockPanelHeight.migratingLegacyTier(rawValue: "small")?.points, 46)
        XCTAssertEqual(DockPanelHeight.migratingLegacyTier(rawValue: "medium")?.points, 54)
        XCTAssertEqual(DockPanelHeight.migratingLegacyTier(rawValue: "large")?.points, 62)
        XCTAssertEqual(DockPanelHeight.migratingLegacyTier(rawValue: "extraLarge")?.points, 70)
        XCTAssertNil(DockPanelHeight.migratingLegacyTier(rawValue: "gigantic"))
    }

    func testEveryHeightKeepsIntegerPointsAndDerivedWindowHeight() {
        for height in sampleHeights {
            let m = height.metrics
            XCTAssertEqual(m.panelHeight, height.points)
            XCTAssertEqual(m.panelHeight.rounded(), m.panelHeight, "条高必须是整数，否则圆角和图标落在半像素上")
            // 这层关系以前只写在注释里，改高度时最容易漏掉窗口高度。
            XCTAssertEqual(m.windowHeight, m.panelHeight + 2 * m.shadowPadding)
            XCTAssertEqual(m.shadowPadding, 20, "阴影边距不随条高缩放——阴影 token 是冻结的")
            XCTAssertEqual(m.capsuleWidth, m.panelHeight, "胶囊是正方形，边长跟面板高度")
        }
    }

    /// 54pt 是基准（`scale == 1`），逐字段锁死。
    ///
    /// **2026-08-16 由 52 改成 54，对齐原生 macOS 26 Dock**（owner 拍板；@2x 截图实测
    /// 原生条高 108px = 54pt）。与之配套的是图标 36→40（`ChipHoverVisual.bareIconSize`）
    /// 与卡高 52→54（`ChipPillMetrics.chipHeight`），三者必须同进同退。
    func testNativeHeightMatchesTheNativeDockBaseline() {
        XCTAssertEqual(DockPanelHeight.native.points, 54)
        XCTAssertEqual(DockPanelHeight.native.scale, 1.0)
        XCTAssertEqual(DockPanelHeight.default, DockPanelHeight.native)
        XCTAssertEqual(DockPanelHeight.native.metrics, PanelLayoutMetrics(
            panelHeight: 54, shadowPadding: 20, windowHeight: 94,
            bottomGap: 8, outerMargin: 12, capsuleWidth: 54, capsuleGap: 8,
            minimumDockWidth: 120, minimumDrawerExtent: 120
        ))
        XCTAssertEqual(PanelLayoutMetrics.tungstenEdge, DockPanelHeight.native.metrics)
    }

    /// 卡片必须撑满条高、上下不留空隙——任务条空白区右键的判定就建立在「没有垂直空隙」上。
    func testChipHeightFillsTheNativePanelExactly() {
        XCTAssertEqual(ChipPillMetrics.chipHeight, DockPanelHeight.native.points)
    }

    func testCapsuleGridContentFitsEveryHeight() {
        // 2 × 2 preview: columns × icon + spacing + 2 × padding must fit the capsule at every height.
        XCTAssertEqual(DrawerCapsulePreviewMetrics.appSlots, 3)
        XCTAssertEqual(DrawerCapsulePreviewMetrics.limit, 7)
        XCTAssertLessThan(DrawerCapsulePreviewMetrics.miniGridWidth, DrawerCapsulePreviewMetrics.iconSize)
        for height in sampleHeights {
            let content = DrawerCapsulePreviewMetrics.contentWidth * height.scale
            XCTAssertLessThanOrEqual(content, height.metrics.capsuleWidth, "\(height.points)pt 胶囊内容超宽")
        }
    }

    func testCapsulePagingSplitsMembersIntoThreesWithTheNextFourAsPreview() {
        let members = (0..<8).map { "app\($0)" }
        XCTAssertEqual(DrawerCapsulePaging.pageCount(memberCount: 0), 1)
        XCTAssertEqual(DrawerCapsulePaging.pageCount(memberCount: 3), 1)
        XCTAssertEqual(DrawerCapsulePaging.pageCount(memberCount: 4), 2)
        XCTAssertEqual(DrawerCapsulePaging.pageCount(memberCount: 8), 3)
        XCTAssertEqual(DrawerCapsulePaging.apps(page: 0, members: members), ["app0", "app1", "app2"])
        XCTAssertEqual(DrawerCapsulePaging.more(page: 0, members: members), ["app3", "app4", "app5", "app6"])
        XCTAssertEqual(DrawerCapsulePaging.apps(page: 2, members: members), ["app6", "app7"])
        XCTAssertEqual(DrawerCapsulePaging.more(page: 2, members: members), [])
        XCTAssertEqual(DrawerCapsulePaging.apps(page: 3, members: members), [])
    }

    func testCapsulePagingTurnsAtMostOnePageAndStaysInRange() {
        XCTAssertEqual(DrawerCapsulePaging.settledPage(page: 1, drag: 0.1, pageCount: 3), 1)
        XCTAssertEqual(DrawerCapsulePaging.settledPage(page: 1, drag: 0.9, pageCount: 3), 2)
        XCTAssertEqual(DrawerCapsulePaging.settledPage(page: 1, drag: -0.2, pageCount: 3), 0)
        XCTAssertEqual(DrawerCapsulePaging.settledPage(page: 2, drag: 0.9, pageCount: 3), 2)
        XCTAssertEqual(DrawerCapsulePaging.settledPage(page: 0, drag: -0.9, pageCount: 3), 0)
        // A member list that shrank under a resting page clamps back into range.
        XCTAssertEqual(DrawerCapsulePaging.settledPage(page: 5, drag: 0, pageCount: 2), 1)
        // ...and a turn from there starts at the page actually shown, not the stale one.
        XCTAssertEqual(DrawerCapsulePaging.settledPage(page: 5, drag: -0.5, pageCount: 2), 0)
    }

    func testCapsuleClickLandsOnThePageNearestToWhatIsShown() {
        XCTAssertEqual(DrawerCapsulePaging.hitPage(page: 1, drag: 0, pageCount: 3), 1)
        XCTAssertEqual(DrawerCapsulePaging.hitPage(page: 1, drag: 0.4, pageCount: 3), 1)
        XCTAssertEqual(DrawerCapsulePaging.hitPage(page: 1, drag: 0.9, pageCount: 3), 2)
        XCTAssertEqual(DrawerCapsulePaging.hitPage(page: 1, drag: -0.9, pageCount: 3), 0)
        XCTAssertEqual(DrawerCapsulePaging.hitPage(page: 2, drag: 0.9, pageCount: 3), 2)
        XCTAssertEqual(DrawerCapsulePaging.hitPage(page: 5, drag: -0.9, pageCount: 2), 0)
    }

    func testCapsulePagingDampsTravelPastEitherEnd() {
        XCTAssertEqual(DrawerCapsulePaging.displayedPosition(page: 1, drag: 0.5, pageCount: 3), 1.5)
        XCTAssertEqual(DrawerCapsulePaging.displayedPosition(page: 0, drag: -1, pageCount: 3),
                       -DrawerCapsulePaging.rubberBand)
        XCTAssertEqual(DrawerCapsulePaging.displayedPosition(page: 2, drag: 1, pageCount: 3),
                       2 + DrawerCapsulePaging.rubberBand)
    }

    func testCapsuleReelWindowHoldsHoverAndBounce() {
        let icon = DrawerCapsulePreviewMetrics.iconSize
        let margin = (DrawerCapsulePreviewMetrics.cellPitch - icon) / 2
        XCTAssertLessThanOrEqual(icon * (DrawerCapsulePreviewMetrics.hoverScale - 1) / 2, margin)
        XCTAssertLessThanOrEqual(DrawerCapsulePreviewMetrics.bounceHeight, margin)
        // The neighbouring page, one pitch away, lies wholly outside the window at rest.
        XCTAssertGreaterThanOrEqual(DrawerCapsulePreviewMetrics.cellPitch - icon / 2,
                                    DrawerCapsulePreviewMetrics.cellPitch / 2)
    }

    func testEveryHeightLaysOutBottomAnchoredAndCentered() {
        let screen = screen(frame: CGRect(x: -1512, y: -400, width: 1512, height: 982))
        for height in sampleHeights {
            let m = height.metrics
            let dock = PanelGeometry.dockTargetFrame(contentWidth: 620, on: screen, metrics: m)
            let capsule = PanelGeometry.capsuleTargetFrame(forDock: dock, on: screen, metrics: m)
            // 非零原点屏幕也必须贴物理底边，且面板高度跟着条高走。
            XCTAssertEqual(dock.minY, screen.frame.minY + m.bottomGap - m.shadowPadding, "\(height.points)pt 底边")
            XCTAssertEqual(dock.height, m.windowHeight, "\(height.points)pt 面板高度")
            // Bar + drawer capsule are centered as one group, not the bar alone.
            let groupMinX = dock.minX + m.shadowPadding
            let groupMaxX = capsule.maxX - m.shadowPadding
            XCTAssertEqual((groupMinX + groupMaxX) / 2, screen.frame.midX, accuracy: 0.5, "\(height.points)pt 整组居中")
            // 胶囊与任务条垂直居中对齐（两者等高时中心重合）。
            XCTAssertEqual(capsule.midY, dock.midY, accuracy: 0.5, "\(height.points)pt 胶囊垂直对齐")
        }
    }

    func testFullBarKeepsOuterMarginOnBothSidesOfTheGroup() {
        let screen = screen(frame: CGRect(x: -1512, y: -400, width: 1512, height: 982))
        for height in sampleHeights {
            let m = height.metrics
            let dock = PanelGeometry.dockTargetFrame(contentWidth: 10_000, on: screen, metrics: m)
            let capsule = PanelGeometry.capsuleTargetFrame(forDock: dock, on: screen, metrics: m)
            let barVisible = dock.insetBy(dx: m.shadowPadding, dy: m.shadowPadding)
            let capsuleVisible = capsule.insetBy(dx: m.shadowPadding, dy: m.shadowPadding)
            XCTAssertEqual(barVisible.minX - screen.frame.minX, m.outerMargin, accuracy: 0.5, "\(height.points)pt 左边距")
            XCTAssertEqual(screen.frame.maxX - capsuleVisible.maxX, m.outerMargin, accuracy: 0.5, "\(height.points)pt 右边距")
            XCTAssertEqual(capsuleVisible.minX - barVisible.maxX, m.capsuleGap, accuracy: 0.5, "\(height.points)pt 胶囊间距")
        }
    }

    func testLiftTargetTracksBarHeight() {
        // 最大化避让的 taskbarTop = 屏幕底 + bottomGap + panelHeight，条高一变必须跟着变，
        // 否则被抬起的窗口底边和新任务条对不上。
        let screenMinY: CGFloat = -400
        let tops = [40, 54, 80].map { DockPanelHeight(clamping: $0).metrics }.map { screenMinY + $0.bottomGap + $0.panelHeight }
        XCTAssertEqual(tops, [-352, -338, -312])
        XCTAssertEqual(tops, tops.sorted(), "抬升目标随条高单调上升")
    }

    private func layout(
        on screen: PanelScreenGeometry,
        contentWidth: CGFloat = 620,
        drawerSize: CGSize = CGSize(width: 210, height: 260)
    ) -> (dock: CGRect, capsule: CGRect, drawer: CGRect) {
        let dock = PanelGeometry.dockTargetFrame(contentWidth: contentWidth, on: screen, metrics: metrics)
        let capsule = PanelGeometry.capsuleTargetFrame(forDock: dock, on: screen, metrics: metrics)
        let drawer = PanelGeometry.drawerTargetFrame(forCapsule: capsule, size: drawerSize, on: screen, metrics: metrics)
        return (dock, capsule, drawer)
    }

    private func screen(frame: CGRect, visibleFrame: CGRect? = nil, safeAreaTop: CGFloat = 0) -> PanelScreenGeometry {
        PanelScreenGeometry(frame: frame, visibleFrame: visibleFrame ?? frame, safeAreaTop: safeAreaTop)
    }
}
