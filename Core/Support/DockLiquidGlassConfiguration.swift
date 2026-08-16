import CoreGraphics
import Foundation

enum DockLiquidGlassRenderPath: Equatable {
    case visualEffectFallback
    case layeredTaskbar
}

struct DockLiquidGlassConfiguration: Equatable {
    let isEnabled: Bool
    let clearTintOpacity: Double
    let whiteOverlayOpacity: Double
    let dimmingOpacity: Double
    let borderOpacity: Double
    let borderLineWidth: Double
    let backgroundMaterialOpacity: Double
    let windowBlurRadius: Double
    let contentInset: Double
    let taskbarHeight: Double
    let taskbarCornerRadius: Double
    let backgroundPlateOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: Double
    let shadowOffsetY: Double

    func renderPath(
        isGlassAPIAvailable: Bool,
        isCompositeAvailable: Bool
    ) -> DockLiquidGlassRenderPath {
        guard isEnabled, isGlassAPIAvailable, isCompositeAvailable else {
            return .visualEffectFallback
        }
        return .layeredTaskbar
    }

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        Self(
            isEnabled: trimmed(environment["DOCK_LIQUID_GLASS"]) == "1",
            clearTintOpacity: boundedDouble(
                environment["DOCK_LIQUID_GLASS_CLEAR_TINT"],
                range: 0 ... 1,
                fallback: 0.4
            ),
            whiteOverlayOpacity: boundedDouble(
                environment["DOCK_LIQUID_GLASS_WHITE_OVERLAY"],
                range: 0 ... 1,
                fallback: 0
            ),
            dimmingOpacity: boundedDouble(
                environment["DOCK_LIQUID_GLASS_DIMMING"],
                range: 0 ... 1,
                fallback: 0
            ),
            borderOpacity: boundedDouble(
                environment["DOCK_LIQUID_GLASS_BORDER"],
                range: 0 ... 1,
                fallback: 0
            ),
            borderLineWidth: boundedDouble(
                environment["DOCK_LIQUID_GLASS_BORDER_WIDTH"],
                range: 0 ... 4,
                fallback: 0
            ),
            backgroundMaterialOpacity: boundedDouble(
                environment["DOCK_LIQUID_GLASS_BACKGROUND_OPACITY"],
                range: 0 ... 1,
                fallback: 0
            ),
            windowBlurRadius: boundedDouble(
                environment["DOCK_LIQUID_GLASS_WINDOW_BLUR"],
                range: 0 ... 64,
                fallback: 6
            ),
            contentInset: boundedDouble(
                environment["DOCK_LIQUID_GLASS_CONTENT_INSET"],
                range: 0 ... 12,
                fallback: 4
            ),
            taskbarHeight: boundedDouble(
                environment["DOCK_LIQUID_GLASS_TASKBAR_HEIGHT"],
                range: 40 ... 100,
                fallback: 55
            ),
            taskbarCornerRadius: boundedDouble(
                environment["DOCK_LIQUID_GLASS_CORNER_RADIUS"],
                range: 0 ... 50,
                fallback: 19.5
            ),
            backgroundPlateOpacity: 0.001,
            shadowOpacity: 0.18,
            shadowRadius: 18,
            shadowOffsetY: -8
        )
    }

    private static func boundedDouble(
        _ raw: String?,
        range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard let raw = trimmed(raw),
              let value = Double(raw),
              value.isFinite,
              range.contains(value) else { return fallback }
        return value
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

enum DockLiquidGlassPanelGeometry {
    static func backgroundFrame(
        for contentPanelFrame: CGRect,
        shadowPadding: CGFloat,
        targetHeight: CGFloat
    ) -> CGRect {
        let legacySurface = shadowPadding > 0
            ? contentPanelFrame.insetBy(dx: shadowPadding, dy: shadowPadding)
            : contentPanelFrame
        guard targetHeight > 0 else { return legacySurface }
        return CGRect(
            x: legacySurface.minX,
            y: legacySurface.maxY - targetHeight,
            width: legacySurface.width,
            height: targetHeight
        )
    }
}

enum DockLiquidGlassPanelRole: Equatable {
    case background
    case content
}

enum DockLiquidGlassPanelLifecyclePlan {
    static func ordering(
        isCompositeActive: Bool,
        shouldShow: Bool
    ) -> [DockLiquidGlassPanelRole] {
        guard isCompositeActive else { return [.content] }
        return shouldShow ? [.background, .content] : [.content, .background]
    }
}
