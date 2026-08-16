import AppKit
import SwiftUI

/// Main-taskbar backdrop. The accepted NSVisualEffectView path remains the fallback; the Liquid
/// Glass path is enabled only after PanelCoordinator has created and verified its background panel.
struct DockGlassBackdrop: View {
    let material: DockPanelMaterial
    var cornerRadius: CGFloat = DockShape.panelCornerRadius
    var saturation: Double = 1.0
    var thicknessEnabled: Bool = false

    var body: some View {
        Group {
            if #available(macOS 26.0, *), DockGlassPresentation.taskbarCompositeActive {
                DockTaskbarLiquidGlass(
                    cornerRadius: cornerRadius,
                    configuration: DockGlassPresentation.configuration
                )
            } else {
                DockVisualEffectView(material: material)
                    .dockBackdropSaturation(saturation)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            DockGlassPresentation.logResolvedPath()
            DockEffectSwitches.logActiveOverrides(
                material: material,
                saturation: saturation,
                thickness: thicknessEnabled
            )
        }
    }
}

extension View {
    func dockBackdropBounds(cornerRadius: CGFloat) -> some View {
        modifier(DockBackdropBoundsModifier(cornerRadius: cornerRadius))
    }

    func dockPanelRim<S: ShapeStyle>(
        cornerRadius: CGFloat,
        style: S,
        lineWidth: CGFloat,
        keepsVisible: Bool = false
    ) -> some View {
        modifier(DockPanelRimModifier(
            cornerRadius: cornerRadius,
            style: style,
            lineWidth: lineWidth,
            keepsVisible: keepsVisible
        ))
    }

    func dockTaskbarShadow(_ shadow: DockShadow) -> some View {
        modifier(DockTaskbarShadowModifier(shadow: shadow))
    }

    func dockTaskbarWindowPadding(_ padding: CGFloat) -> some View {
        modifier(DockTaskbarWindowPaddingModifier(padding: padding))
    }
}

private struct DockBackdropBoundsModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if DockGlassPresentation.taskbarCompositeActive {
            content.ignoresSafeArea()
        } else {
            content
                .padding(-2)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .ignoresSafeArea()
        }
    }
}

private struct DockPanelRimModifier<S: ShapeStyle>: ViewModifier {
    let cornerRadius: CGFloat
    let style: S
    let lineWidth: CGFloat
    let keepsVisible: Bool

    func body(content: Content) -> some View {
        let effectiveWidth = DockGlassPresentation.taskbarCompositeActive && !keepsVisible
            ? 0
            : lineWidth
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(style, lineWidth: effectiveWidth)
        }
    }
}

private struct DockTaskbarShadowModifier: ViewModifier {
    let shadow: DockShadow

    @ViewBuilder
    func body(content: Content) -> some View {
        if DockGlassPresentation.taskbarCompositeActive {
            content
        } else {
            content.dockShadow(shadow)
        }
    }
}

private struct DockTaskbarWindowPaddingModifier: ViewModifier {
    let padding: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if DockGlassPresentation.taskbarCompositeActive {
            content
        } else {
            content.padding(padding)
        }
    }
}

enum DockGlassPresentation {
    static let configuration = DockLiquidGlassConfiguration.resolve()
    private(set) static var taskbarCompositeActive = false

    static var shouldAttemptTaskbarComposite: Bool {
        guard #available(macOS 26.0, *), configuration.isEnabled else { return false }
        return TEDockGlassCanSetWindowBackgroundBlur()
    }

    static func setTaskbarCompositeActive(_ active: Bool) {
        taskbarCompositeActive = active
    }

    static func logResolvedPath() {
        guard configuration.isEnabled else { return }
        if taskbarCompositeActive {
            print(
                "[glass] taskbar composite active, clearTint=\(configuration.clearTintOpacity), "
                    + "background=\(configuration.backgroundMaterialOpacity), "
                    + "windowBlur=\(configuration.windowBlurRadius)"
            )
        } else if #available(macOS 26.0, *) {
            print("[glass] composite unavailable; using NSVisualEffectView")
        } else {
            print("[glass] enabled but macOS < 26; using NSVisualEffectView")
        }
    }
}

@available(macOS 26.0, *)
private struct DockTaskbarLiquidGlass: View {
    let cornerRadius: CGFloat
    let configuration: DockLiquidGlassConfiguration

    var body: some View {
        let inset = CGFloat(configuration.contentInset)
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius + inset,
            style: .continuous
        ).inset(by: inset)
        let tint = Color(nsColor: NSColor(deviceWhite: 127.0 / 255.0, alpha: 1))
            .opacity(configuration.clearTintOpacity)

        shape
            .fill(Color.clear)
            .glassEffect(.clear.tint(tint).interactive(false), in: shape)
            .background {
                shape.fill(Color.white.opacity(configuration.whiteOverlayOpacity))
            }
            .overlay {
                if configuration.dimmingOpacity > 0 {
                    shape.fill(Color.black.opacity(configuration.dimmingOpacity))
                }
            }
            .overlay { directionalBorder(for: shape) }
            .materialActiveAppearance(.active)
            .environment(\.appearsActive, true)
            .padding(-inset)
    }

    private func directionalBorder<S: InsettableShape>(for shape: S) -> some View {
        let opacity = configuration.borderOpacity
        let width = CGFloat(configuration.borderLineWidth)
        return ZStack {
            shape.strokeBorder(Color.white.opacity(opacity * 0.24), lineWidth: width)

            shape
                .strokeBorder(Color.white.opacity(opacity), lineWidth: width)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white.opacity(0.9), location: 0.18),
                            .init(color: .clear, location: 0.62),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

            shape
                .strokeBorder(Color.black.opacity(opacity * 0.22), lineWidth: max(0.5, width * 0.7))
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.58),
                            .init(color: .white.opacity(0.75), location: 0.82),
                            .init(color: .white, location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .compositingGroup()
    }
}

/// WindowServer-facing half of the taskbar composite. It lives in a dedicated mouse-transparent
/// panel so the 6pt window blur does not reprocess the SwiftUI glass in the content window.
final class DockTaskbarLiquidGlassBackgroundView: NSView {
    private let liveBackdropSubscriptionView = NSVisualEffectView()
    private let materialView = NSVisualEffectView()
    private let blurStrengthOverlayView = NSView()
    private var configuration: DockLiquidGlassConfiguration
    private var plateCornerRadius: CGFloat

    init(
        frame frameRect: NSRect,
        cornerRadius: CGFloat,
        configuration: DockLiquidGlassConfiguration
    ) {
        self.configuration = configuration
        self.plateCornerRadius = cornerRadius
        super.init(frame: frameRect)

        wantsLayer = true
        // Each effect subview owns the rounded clip. Keep the root unclipped so its dedicated
        // shadow is not cut off at the plate edge.
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(configuration.shadowOpacity)
        layer?.shadowRadius = configuration.shadowRadius
        layer?.shadowOffset = CGSize(width: 0, height: configuration.shadowOffsetY)
        configureVisualEffectView(liveBackdropSubscriptionView)
        liveBackdropSubscriptionView.material = .underWindowBackground
        liveBackdropSubscriptionView.alphaValue = 3.0 / 255.0

        configureVisualEffectView(materialView)
        materialView.material = .menu
        materialView.alphaValue = configuration.backgroundMaterialOpacity

        blurStrengthOverlayView.wantsLayer = true
        for view in [liveBackdropSubscriptionView, materialView, blurStrengthOverlayView] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        apply(cornerRadius: cornerRadius, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateOverlayColor()
    }

    func apply(
        cornerRadius: CGFloat,
        configuration: DockLiquidGlassConfiguration
    ) {
        self.configuration = configuration
        plateCornerRadius = cornerRadius
        materialView.alphaValue = configuration.backgroundMaterialOpacity
        materialView.isHidden = configuration.backgroundMaterialOpacity <= 0
        blurStrengthOverlayView.isHidden = configuration.dimmingOpacity <= 0
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.black
            .withAlphaComponent(configuration.backgroundPlateOpacity)
            .cgColor
        layer?.shadowOpacity = Float(configuration.shadowOpacity)
        layer?.shadowRadius = configuration.shadowRadius
        layer?.shadowOffset = CGSize(width: 0, height: configuration.shadowOffsetY)
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        for view in [liveBackdropSubscriptionView, materialView, blurStrengthOverlayView] {
            view.wantsLayer = true
            view.layer?.cornerRadius = cornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
        updateOverlayColor()
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: plateCornerRadius,
            cornerHeight: plateCornerRadius,
            transform: nil
        )
    }

    private func configureVisualEffectView(_ view: NSVisualEffectView) {
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
    }

    private func updateOverlayColor() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = isDark ? NSColor.black : NSColor.white
        blurStrengthOverlayView.layer?.backgroundColor = color
            .withAlphaComponent(configuration.dimmingOpacity)
            .cgColor
    }
}
