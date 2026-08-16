import AppKit
import SwiftUI

/// 悬浮面板底板：`macOS 26 + 开关打开 + 背景窗口建好` 时走原生 Liquid Glass，否则走
/// 既有的毛玻璃材质。
///
/// **`usesLiquidGlass` 是显式传进来的，没有默认值** —— 同 `scale` / `hoverStyle` 的既有规矩
/// （`AGENTS.md`《Taskbar Size Tiers》）：漏传是编译错误，而不是静默按某一条路径渲染。
/// 曾经它是个可变静态量，SwiftUI 观察不到，面板拆除后视图仍会读到旧值。
struct DockGlassBackdrop: View {
    /// 回退路径用的材质（`DockThemeTokens.panelMaterial`）。玻璃不可用时就是它。
    let material: DockPanelMaterial
    let usesLiquidGlass: Bool
    var cornerRadius: CGFloat = DockShape.panelCornerRadius
    var saturation: Double = 1.0
    var thicknessEnabled: Bool = false

    var body: some View {
        Group {
            if #available(macOS 26.0, *), usesLiquidGlass {
                DockLiquidGlassPlate(
                    cornerRadius: cornerRadius,
                    configuration: DockGlassPresentation.configuration
                )
                // 玻璃自己就是一块视图，要显式退出命中测试；
                // **不能挂在 Group 外面** —— 那样回退路径也会跟着变，而回退路径必须逐像素、
                // 逐行为等于改造前。
                .allowsHitTesting(false)
            } else {
                DockVisualEffectView(material: material)
                    .dockBackdropSaturation(saturation)
            }
        }
        .onAppear {
            DockGlassPresentation.logResolvedPath(compositeActive: usesLiquidGlass)
            DockEffectSwitches.logActiveOverrides(
                material: material,
                saturation: saturation,
                thickness: thicknessEnabled
            )
        }
    }
}

extension View {
    /// 面板描边。玻璃自带边缘高光，玻璃态下我们自己那圈常驻描边要关掉；
    /// 但拖放命中的整框高亮（`keepsVisible`）两条路径都要画。
    func dockPanelRim<S: ShapeStyle>(
        cornerRadius: CGFloat,
        style: S,
        lineWidth: CGFloat,
        usesLiquidGlass: Bool,
        keepsVisible: Bool = false
    ) -> some View {
        let effectiveWidth = usesLiquidGlass && !keepsVisible ? 0 : lineWidth
        return overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(style, lineWidth: effectiveWidth)
        }
    }
}

enum DockGlassPresentation {
    static let configuration = DockLiquidGlassConfiguration.resolve()

    /// 能不能给任务条建玻璃合成。三道门：系统 ≥ 26、开关打开、SkyLight 的两个符号都取到。
    static var shouldAttemptTaskbarComposite: Bool {
        let glassAvailable: Bool
        if #available(macOS 26.0, *) { glassAvailable = true } else { glassAvailable = false }
        // 短路：低版本不去 dlopen SkyLight。
        let compositeAvailable = glassAvailable && TEDockGlassCanSetWindowBackgroundBlur()
        return configuration.renderPath(
            isGlassAPIAvailable: glassAvailable,
            isCompositeAvailable: compositeAvailable
        ) == .layeredTaskbar
    }

    /// 启动时打一行说明这次跑的是哪条路径。用 `print` 而不是 `Logger` —— 有些环境读不回
    /// 统一日志（同 `[edgehover]` 的理由）。
    static func logResolvedPath(compositeActive: Bool) {
        guard configuration.isEnabled else { return }
        if compositeActive {
            print(
                "[glass] taskbar composite active, clearTint=\(configuration.clearTintOpacity), "
                    + "border=\(configuration.borderOpacity)/\(configuration.borderLineWidth), "
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

/// 玻璃底板本体。五个悬浮面板共用（探路期只有任务条接了）。
@available(macOS 26.0, *)
private struct DockLiquidGlassPlate: View {
    let cornerRadius: CGFloat
    let configuration: DockLiquidGlassConfiguration

    var body: some View {
        let inset = CGFloat(configuration.contentInset)
        // 先外扩再内缩：给玻璃自己的边缘渲染留余量，最后用负 padding 把布局尺寸还原。
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
            .overlay { directionalBorder(for: shape) }
            // 面板永远不会成为 key 窗口，不强制的话材质会按「非活动」渲染、整块发灰。
            .materialActiveAppearance(.active)
            .environment(\.appearsActive, true)
            .padding(-inset)
    }

    /// 方向性描边：整圈底色 + 左上到右下的亮边 + 右下的暗收，模拟光从上方进入介质。
    /// 原生 Dock 的立体感主要来自这一圈。
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

/// 玻璃合成的 WindowServer 侧。它独占一个鼠标穿透的面板，这样窗口模糊不会把内容窗口里的
/// SwiftUI 玻璃再合成一遍。
///
/// **这里不画阴影。** 本视图所在窗口的 frame 正好等于底板本身，图层阴影画在窗口外会被整个
/// 裁掉；落地阴影归内容窗口的 `.dockShadow`，它有 20pt 透明边可用。
final class DockTaskbarLiquidGlassBackgroundView: NSView {
    private let liveBackdropSubscriptionView = NSVisualEffectView()
    private let materialView = NSVisualEffectView()
    private let dimmingOverlayView = NSView()
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
        configureVisualEffectView(liveBackdropSubscriptionView)
        // 极低 alpha 的订阅层：让 WindowServer 持续把背后内容喂给这个窗口，
        // 否则背景模糊会停在某一帧。
        liveBackdropSubscriptionView.material = .underWindowBackground
        liveBackdropSubscriptionView.alphaValue = 3.0 / 255.0

        configureVisualEffectView(materialView)
        materialView.material = .menu
        materialView.alphaValue = configuration.backgroundMaterialOpacity

        dimmingOverlayView.wantsLayer = true
        for view in [liveBackdropSubscriptionView, materialView, dimmingOverlayView] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        apply(cornerRadius: cornerRadius, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        guard cornerRadius != plateCornerRadius || configuration != self.configuration else { return }
        self.configuration = configuration
        plateCornerRadius = cornerRadius
        materialView.alphaValue = configuration.backgroundMaterialOpacity
        materialView.isHidden = configuration.backgroundMaterialOpacity <= 0
        dimmingOverlayView.isHidden = configuration.dimmingOpacity <= 0
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        // 不是观感层：WindowServer 需要一块非零 alpha 的形状才肯做背景模糊。
        layer?.backgroundColor = NSColor.black
            .withAlphaComponent(configuration.backgroundPlateOpacity)
            .cgColor
        for view in [liveBackdropSubscriptionView, materialView, dimmingOverlayView] {
            view.wantsLayer = true
            view.layer?.cornerRadius = cornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
        updateOverlayColor()
    }

    private func configureVisualEffectView(_ view: NSVisualEffectView) {
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
    }

    private func updateOverlayColor() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = isDark ? NSColor.black : NSColor.white
        dimmingOverlayView.layer?.backgroundColor = color
            .withAlphaComponent(configuration.dimmingOpacity)
            .cgColor
    }
}
