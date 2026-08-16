import XCTest
@testable import macos_dock_cc_v2

final class DockLiquidGlassConfigurationTests: XCTestCase {
    func testDefaultKeepsAcceptedVisualEffectPath() {
        let configuration = DockLiquidGlassConfiguration.resolve(environment: [:])

        XCTAssertFalse(configuration.isEnabled)
        XCTAssertEqual(configuration.clearTintOpacity, 0.4)
        XCTAssertEqual(configuration.whiteOverlayOpacity, 0)
        XCTAssertEqual(configuration.dimmingOpacity, 0)
        XCTAssertEqual(configuration.borderOpacity, 0.55, "边缘高光是「像不像原生」最便宜的一档，不能是 0")
        XCTAssertEqual(configuration.borderLineWidth, 1)
        XCTAssertEqual(configuration.backgroundMaterialOpacity, 0)
        XCTAssertEqual(configuration.windowBlurRadius, 6)
        XCTAssertEqual(configuration.contentInset, 4)
        XCTAssertEqual(configuration.backgroundPlateOpacity, 0.001)
        XCTAssertEqual(
            configuration.renderPath(isGlassAPIAvailable: true, isCompositeAvailable: true),
            .visualEffectFallback
        )
    }

    func testEnableSwitchOnlyAcceptsOne() {
        XCTAssertTrue(resolve(["DOCK_LIQUID_GLASS": "1"]).isEnabled)
        XCTAssertTrue(resolve(["DOCK_LIQUID_GLASS": " 1 \n"]).isEnabled)

        for value in ["", "0", "true", "yes", "2"] {
            XCTAssertFalse(resolve(["DOCK_LIQUID_GLASS": value]).isEnabled)
        }
    }

    func testCompositeRequiresSystemAPIAndBackgroundPanel() {
        let configuration = resolve(["DOCK_LIQUID_GLASS": "1"])

        XCTAssertEqual(
            configuration.renderPath(isGlassAPIAvailable: true, isCompositeAvailable: true),
            .layeredTaskbar
        )
        XCTAssertEqual(
            configuration.renderPath(isGlassAPIAvailable: false, isCompositeAvailable: true),
            .visualEffectFallback
        )
        XCTAssertEqual(
            configuration.renderPath(isGlassAPIAvailable: true, isCompositeAvailable: false),
            .visualEffectFallback
        )
    }

    func testNumericOverridesAcceptBounds() {
        let configuration = resolve([
            "DOCK_LIQUID_GLASS_CLEAR_TINT": "0",
            "DOCK_LIQUID_GLASS_WHITE_OVERLAY": "1",
            "DOCK_LIQUID_GLASS_DIMMING": "1",
            "DOCK_LIQUID_GLASS_BORDER": "1",
            "DOCK_LIQUID_GLASS_BORDER_WIDTH": "4",
            "DOCK_LIQUID_GLASS_BACKGROUND_OPACITY": "0",
            "DOCK_LIQUID_GLASS_WINDOW_BLUR": "64",
            "DOCK_LIQUID_GLASS_CONTENT_INSET": "12",
        ])

        XCTAssertEqual(configuration.clearTintOpacity, 0)
        XCTAssertEqual(configuration.whiteOverlayOpacity, 1)
        XCTAssertEqual(configuration.dimmingOpacity, 1)
        XCTAssertEqual(configuration.borderOpacity, 1)
        XCTAssertEqual(configuration.borderLineWidth, 4)
        XCTAssertEqual(configuration.backgroundMaterialOpacity, 0)
        XCTAssertEqual(configuration.windowBlurRadius, 64)
        XCTAssertEqual(configuration.contentInset, 12)
    }

    func testInvalidNumericOverridesUseCandidateDefaults() {
        let invalidValues = ["", "abc", "nan", "inf", "-1", "999"]
        for value in invalidValues {
            let configuration = resolve([
                "DOCK_LIQUID_GLASS_CLEAR_TINT": value,
                "DOCK_LIQUID_GLASS_WHITE_OVERLAY": value,
                "DOCK_LIQUID_GLASS_DIMMING": value,
                "DOCK_LIQUID_GLASS_BORDER": value,
                "DOCK_LIQUID_GLASS_BORDER_WIDTH": value,
                "DOCK_LIQUID_GLASS_BACKGROUND_OPACITY": value,
                "DOCK_LIQUID_GLASS_WINDOW_BLUR": value,
                "DOCK_LIQUID_GLASS_CONTENT_INSET": value,
            ])
            XCTAssertEqual(configuration.clearTintOpacity, 0.4, "clear tint: \(value)")
            XCTAssertEqual(configuration.whiteOverlayOpacity, 0, "white overlay: \(value)")
            XCTAssertEqual(configuration.dimmingOpacity, 0, "dimming: \(value)")
            XCTAssertEqual(configuration.borderOpacity, 0.55, "border: \(value)")
            XCTAssertEqual(configuration.borderLineWidth, 1, "border width: \(value)")
            XCTAssertEqual(configuration.backgroundMaterialOpacity, 0, "background: \(value)")
            XCTAssertEqual(configuration.windowBlurRadius, 6, "window blur: \(value)")
            XCTAssertEqual(configuration.contentInset, 4, "content inset: \(value)")
        }
    }

    /// 背景窗口 = 内容窗口减掉 20pt 阴影透明边后的可视底板，高度由 `DockSize.metrics` 决定
    /// （92 − 2×20 = 52 = 中档面板高），**不再有玻璃自带的第二套高度**。
    func testBackgroundFrameIsTheVisiblePlateInsideTheShadowPadding() {
        XCTAssertEqual(
            DockLiquidGlassPanelGeometry.backgroundFrame(
                for: CGRect(x: 80, y: 10, width: 440, height: 92),
                shadowPadding: 20
            ),
            CGRect(x: 100, y: 30, width: 400, height: 52)
        )
    }

    func testBackgroundFrameIsIdentityWithoutShadowPadding() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        XCTAssertEqual(
            DockLiquidGlassPanelGeometry.backgroundFrame(for: frame, shadowPadding: 0),
            frame
        )
        XCTAssertEqual(
            DockLiquidGlassPanelGeometry.backgroundFrame(for: frame, shadowPadding: -2),
            frame,
            "负值不该把窗口撑大"
        )
    }

    func testCompositePanelLifecycleOrderingIsAtomic() {
        XCTAssertEqual(
            DockLiquidGlassPanelLifecyclePlan.ordering(
                isCompositeActive: true,
                shouldShow: true
            ),
            [.background, .content]
        )
        XCTAssertEqual(
            DockLiquidGlassPanelLifecyclePlan.ordering(
                isCompositeActive: true,
                shouldShow: false
            ),
            [.content, .background]
        )
        XCTAssertEqual(
            DockLiquidGlassPanelLifecyclePlan.ordering(
                isCompositeActive: false,
                shouldShow: true
            ),
            [.content]
        )
        XCTAssertEqual(
            DockLiquidGlassPanelLifecyclePlan.ordering(
                isCompositeActive: false,
                shouldShow: false
            ),
            [.content]
        )
    }

    private func resolve(_ environment: [String: String]) -> DockLiquidGlassConfiguration {
        DockLiquidGlassConfiguration.resolve(environment: environment)
    }
}
