import XCTest
@testable import macos_dock_cc_v2

/// 松手归位飞行的纯判定。这里钉的核心是**坐标换算**：屏幕是左下原点、载体面板是左上原点，
/// 两者搞混的话图标会朝屏幕另一头飞——而那种错误在肉眼验收里只会被说成「动画怪怪的」。
final class DragLandingPlanTests: XCTestCase {
    /// 主屏 1512×982，载体面板永远铺满整屏。
    private let carrier = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testAnchorCentreConvertsToCarrierPanelCoordinates() {
        // 任务条上一张 40×54 的卡，可视区底边在 y=8（屏幕左下原点）。
        let slot = CGRect(x: 700, y: 8, width: 40, height: 54)
        let flight = DragLandingPlan.flight(from: CGPoint(x: 900, y: 400),
                                            fromScale: DragLandingPlan.carriedScale,
                                            anchorScreenRect: slot,
                                            carrierScreenFrame: carrier)
        // 中心 x = 720；y 要翻过来：982 − 35 = 947（面板内左上原点）。
        XCTAssertEqual(flight?.to.x, 720)
        XCTAssertEqual(flight?.to.y, 947)
    }

    /// 载体面板不在主屏原点时（外接屏），换算要减去面板自己的原点。
    func testCarrierOriginIsSubtracted() {
        let external = CGRect(x: -504, y: 982, width: 2560, height: 1440)
        let slot = CGRect(x: 0, y: 1000, width: 40, height: 54)
        let flight = DragLandingPlan.flight(from: .zero,
                                            fromScale: 1,
                                            anchorScreenRect: slot,
                                            carrierScreenFrame: external)
        XCTAssertEqual(flight?.to.x, 20 - (-504))
        XCTAssertEqual(flight?.to.y, (982 + 1440) - 1027)
    }

    /// 起点与起始缩放原样带出去：载体在投放区里是缩着的（0.82），飞行必须从那个尺寸开始，
    /// 否则松手一瞬间会先跳大再飞。
    func testStartStateIsCarriedThrough() {
        let flight = DragLandingPlan.flight(from: CGPoint(x: 123, y: 456),
                                            fromScale: DragLandingPlan.dropZoneScale,
                                            anchorScreenRect: CGRect(x: 0, y: 0, width: 40, height: 40),
                                            carrierScreenFrame: carrier)
        XCTAssertEqual(flight?.from, CGPoint(x: 123, y: 456))
        XCTAssertEqual(flight?.fromScale, DragLandingPlan.dropZoneScale)
    }

    /// 终点缩放恒为 1：落地那一刻必须和条上那张卡逐像素同尺寸，不然收载体时会闪一下。
    func testAlwaysLandsAtNativeScale() {
        for start in [DragLandingPlan.carriedScale, DragLandingPlan.dropZoneScale] {
            let flight = DragLandingPlan.flight(from: .zero, fromScale: start,
                                                anchorScreenRect: CGRect(x: 0, y: 0, width: 40, height: 40),
                                                carrierScreenFrame: carrier)
            XCTAssertEqual(flight?.toScale, 1.0)
        }
    }

    // MARK: - 不飞的情形（一律退回改造前的瞬时收尾，零风险）

    /// 拿不到落点 → 不飞。转正进任务条那一支就是这种：松手会解冻条宽、整条重新居中，
    /// 落点在飞行途中还会漂，与其飞歪不如不飞。
    func testNoAnchorMeansNoFlight() {
        XCTAssertNil(DragLandingPlan.flight(from: .zero, fromScale: 1,
                                            anchorScreenRect: nil, carrierScreenFrame: carrier))
    }

    /// 还没量到的帧（`.zero` / 零宽高）不能当落点——那会让图标飞到屏幕左下角。
    func testUnmeasuredAnchorIsRejected() {
        XCTAssertNil(DragLandingPlan.flight(from: .zero, fromScale: 1,
                                            anchorScreenRect: .zero, carrierScreenFrame: carrier))
        XCTAssertNil(DragLandingPlan.flight(from: .zero, fromScale: 1,
                                            anchorScreenRect: CGRect(x: 10, y: 10, width: 0, height: 54),
                                            carrierScreenFrame: carrier))
    }

    /// 载体面板还没建起来（frame 为空）同理。
    func testEmptyCarrierFrameIsRejected() {
        XCTAssertNil(DragLandingPlan.flight(from: .zero, fromScale: 1,
                                            anchorScreenRect: CGRect(x: 0, y: 0, width: 40, height: 40),
                                            carrierScreenFrame: .zero))
    }

    // MARK: - 时长按距离取（owner 2026-08-18：「没有原生的动画从容优雅」）

    /// 定长会让短距离显得急、长距离显得赶。距离越远飞得越久，但两端都有闸。
    func testDurationGrowsWithDistanceAndIsClampedAtBothEnds() {
        XCTAssertEqual(DragLandingPlan.duration(travel: 0), DragLandingPlan.minimumDuration)
        XCTAssertEqual(DragLandingPlan.duration(travel: DragLandingPlan.referenceTravel),
                       DragLandingPlan.maximumFlightDuration, accuracy: 0.0001)
        // 再远也不加了，否则跨屏那种超长距离会拖沓。
        XCTAssertEqual(DragLandingPlan.duration(travel: 5000),
                       DragLandingPlan.maximumFlightDuration, accuracy: 0.0001)
        // 负数（不该出现）也不能穿到下界以下。
        XCTAssertEqual(DragLandingPlan.duration(travel: -10), DragLandingPlan.minimumDuration)
    }

    /// 开根号而不是线性：**近距离要比线性更慷慨**，不然小归位一闪而过看不见。
    func testShortTravelIsMoreGenerousThanLinear() {
        let quarter = DragLandingPlan.referenceTravel / 4
        let linear = DragLandingPlan.minimumDuration
            + (DragLandingPlan.maximumFlightDuration - DragLandingPlan.minimumDuration) * 0.25
        XCTAssertGreaterThan(DragLandingPlan.duration(travel: quarter), linear)
    }

    /// 每一次飞行都自带时长，视图和计时器读的是同一个值——分开算过就会漂。
    func testFlightCarriesItsOwnDuration() {
        let near = DragLandingPlan.flight(from: CGPoint(x: 100, y: 100), fromScale: 1,
                                          anchorScreenRect: CGRect(x: 90, y: 870, width: 40, height: 54),
                                          carrierScreenFrame: carrier)
        let far = DragLandingPlan.flight(from: CGPoint(x: 100, y: 100), fromScale: 1,
                                         anchorScreenRect: CGRect(x: 1200, y: 8, width: 40, height: 54),
                                         carrierScreenFrame: carrier)
        XCTAssertNotNil(near?.duration)
        XCTAssertLessThan(near!.duration, far!.duration)
    }

    /// **点击时的手抖不该触发归位飞行**：起拖门槛只有 8pt，手一抖就算一次微小拖动，
    /// 而最短飞行 0.60s 会让这种零距离归位变成一个原地慢慢晃回去的可见影子
    ///（owner 2026-08-18：「点击图标隔壁的图标会有上下的重影」）。
    func testTinyTravelSkipsTheFlightEntirely() {
        let slot = CGRect(x: 700, y: 8, width: 40, height: 54)
        // 落点就在起点边上（位移 ~5pt）→ 不飞。
        let centre = CGPoint(x: 720, y: 982 - 35)
        let jitter = CGPoint(x: centre.x + 4, y: centre.y + 3)
        XCTAssertNil(DragLandingPlan.flight(from: jitter, fromScale: 1,
                                            anchorScreenRect: slot, carrierScreenFrame: carrier))
    }

    /// 真的拖开了就照飞不误——门槛只挡手抖，不能把短距离的真拖动一起挡掉。
    func testTravelBeyondTheThresholdStillFlies() {
        let slot = CGRect(x: 700, y: 8, width: 40, height: 54)
        let away = CGPoint(x: 720 + DragLandingPlan.minimumTravel + 6, y: 982 - 35)
        XCTAssertNotNil(DragLandingPlan.flight(from: away, fromScale: 1,
                                               anchorScreenRect: slot, carrierScreenFrame: carrier))
    }

    /// 门槛必须比起拖门槛（8pt）大，否则挡不住手抖；也不能大到吃掉真拖动。
    func testThresholdSitsJustAboveTheDragGesture() {
        XCTAssertGreaterThan(DragLandingPlan.minimumTravel, 8)
        XCTAssertLessThan(DragLandingPlan.minimumTravel, 30)
    }

    // MARK: - 中途纠偏的时间闸（owner 2026-08-18：落地有几率抖）

    /// 快到上限时**不许**再纠偏：那时候重新起飞一段必然被上限截断，
    /// 反而制造出要治的那一下跳。
    func testRetargetIsRefusedNearTheDeadline() {
        XCTAssertFalse(DragLandingPlan.allowsRetarget(remainingBeforeDeadline: 0))
        XCTAssertFalse(DragLandingPlan.allowsRetarget(
            remainingBeforeDeadline: DragLandingPlan.duration))
        XCTAssertFalse(DragLandingPlan.allowsRetarget(remainingBeforeDeadline: -1))
    }

    /// 时间还够就允许——纠偏本身是治「卡槽还在动、终点会漂」的手段，不能一刀切掉。
    func testRetargetIsAllowedWhileThereIsRoomForAWholeFlight() {
        XCTAssertTrue(DragLandingPlan.allowsRetarget(
            remainingBeforeDeadline: DragLandingPlan.maximumDuration))
    }

    /// 上限必须容得下至少一次完整的纠偏重飞，否则那个闸永远是关的、纠偏形同虚设。
    func testDeadlineLeavesRoomForAtLeastOneRetarget() {
        XCTAssertGreaterThan(DragLandingPlan.maximumDuration,
                             2 * (DragLandingPlan.duration + DragLandingPlan.settleMargin))
    }

    /// 交接淡出要足够短，读起来仍是「一落地就交接完了」，而不是一段可见的淡出。
    func testHandoffFadeStaysImperceptible() {
        XCTAssertLessThan(DragLandingPlan.handoffFade, DragLandingPlan.duration / 2)
    }
}
