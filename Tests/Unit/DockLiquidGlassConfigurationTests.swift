import XCTest
@testable import macos_dock_cc_v2

final class DockLiquidGlassConfigurationTests: XCTestCase {
    func testDefaultKeepsAcceptedVisualEffectPath() {
        let configuration = DockLiquidGlassConfiguration.resolve(environment: [:])

        XCTAssertFalse(configuration.isEnabled)
        XCTAssertEqual(configuration.clearTintOpacity, 0.4)
        XCTAssertEqual(configuration.whiteOverlayOpacity, 0)
        XCTAssertEqual(configuration.dimmingOpacity, 0)
        XCTAssertEqual(configuration.borderOpacity, 0)
        XCTAssertEqual(configuration.borderLineWidth, 0)
        XCTAssertEqual(configuration.backgroundMaterialOpacity, 0)
        XCTAssertEqual(configuration.windowBlurRadius, 6)
        XCTAssertEqual(configuration.contentInset, 4)
        XCTAssertEqual(configuration.taskbarHeight, 55)
        XCTAssertEqual(configuration.taskbarCornerRadius, 19.5)
        XCTAssertEqual(configuration.backgroundPlateOpacity, 0.001)
        XCTAssertEqual(configuration.shadowOpacity, 0.18)
        XCTAssertEqual(configuration.shadowRadius, 18)
        XCTAssertEqual(configuration.shadowOffsetY, -8)
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
            "DOCK_LIQUID_GLASS_TASKBAR_HEIGHT": "100",
            "DOCK_LIQUID_GLASS_CORNER_RADIUS": "50",
        ])

        XCTAssertEqual(configuration.clearTintOpacity, 0)
        XCTAssertEqual(configuration.whiteOverlayOpacity, 1)
        XCTAssertEqual(configuration.dimmingOpacity, 1)
        XCTAssertEqual(configuration.borderOpacity, 1)
        XCTAssertEqual(configuration.borderLineWidth, 4)
        XCTAssertEqual(configuration.backgroundMaterialOpacity, 0)
        XCTAssertEqual(configuration.windowBlurRadius, 64)
        XCTAssertEqual(configuration.contentInset, 12)
        XCTAssertEqual(configuration.taskbarHeight, 100)
        XCTAssertEqual(configuration.taskbarCornerRadius, 50)
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
                "DOCK_LIQUID_GLASS_TASKBAR_HEIGHT": value,
                "DOCK_LIQUID_GLASS_CORNER_RADIUS": value,
            ])
            XCTAssertEqual(configuration.clearTintOpacity, 0.4, "clear tint: \(value)")
            XCTAssertEqual(configuration.whiteOverlayOpacity, 0, "white overlay: \(value)")
            XCTAssertEqual(configuration.dimmingOpacity, 0, "dimming: \(value)")
            XCTAssertEqual(configuration.borderOpacity, 0, "border: \(value)")
            XCTAssertEqual(configuration.borderLineWidth, 0, "border width: \(value)")
            XCTAssertEqual(configuration.backgroundMaterialOpacity, 0, "background: \(value)")
            XCTAssertEqual(configuration.windowBlurRadius, 6, "window blur: \(value)")
            XCTAssertEqual(configuration.contentInset, 4, "content inset: \(value)")
            XCTAssertEqual(configuration.taskbarHeight, 55, "taskbar height: \(value)")
            XCTAssertEqual(configuration.taskbarCornerRadius, 19.5, "corner radius: \(value)")
        }
    }

    func testBackgroundFrameRemovesShadowPaddingAndKeepsLegacyTopEdge() {
        XCTAssertEqual(
            DockLiquidGlassPanelGeometry.backgroundFrame(
                for: CGRect(x: 80, y: 10, width: 440, height: 92),
                shadowPadding: 20,
                targetHeight: 55
            ),
            CGRect(x: 100, y: 27, width: 400, height: 55)
        )
    }

    func testBackgroundFrameUsesTargetHeightWithoutShadowPadding() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        XCTAssertEqual(
            DockLiquidGlassPanelGeometry.backgroundFrame(
                for: frame,
                shadowPadding: 0,
                targetHeight: 55
            ),
            CGRect(x: 10, y: 5, width: 100, height: 55)
        )
        XCTAssertEqual(
            DockLiquidGlassPanelGeometry.backgroundFrame(
                for: frame,
                shadowPadding: -2,
                targetHeight: 0
            ),
            frame
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
