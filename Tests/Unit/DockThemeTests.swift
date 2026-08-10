import XCTest
@testable import macos_dock_cc_v2

/// **深色冻结测试。**
///
/// 浅色模式适配（2026-07-30）把散落在 8 个视图文件里的约 50 处写死颜色收拢进 `DockThemeTokens`。
/// owner 定的硬边界是「深色观感一点不变」——本文件就是那条边界的机械保证：下面每一个期望值都是
/// 改造**前**该处代码里的字面值，逐项抄录。任何人以后顺手调深色数值，这里会直接红。
///
/// 要改观感请改 `DockThemeTokens.light`。如果确实要动深色，那是一个需要 owner 拍板的产品决策，
/// 改完请同步更新本文件——**不要**因为测试红了就把期望值改成新值了事。
final class DockThemeTests: XCTestCase {

    private let dark = DockThemeTokens.dark
    private let light = DockThemeTokens.light

    /// 面板留给阴影的透明边距。读 `PanelLayoutMetrics`（`PanelCoordinator.shadowPadding` 只是它的转发，
    /// 而 PanelCoordinator 没编进测试 target）。
    private let shadowPadding = PanelLayoutMetrics.tungstenEdge.shadowPadding

    // MARK: - 深色逐项冻结

    // 面板描边：改造前是均匀一圈 white 0.15（DockStripView / DrawerView / 两个弹窗 / 胶囊 共 5 处），
    // 高亮态 white 0.45 + 线宽 1。上下同值 → 渐变退化成均匀色，与改造前逐像素一致。
    func testDarkPanelRimMatchesLegacyLiterals() {
        XCTAssertEqual(dark.panelRimTop, .white(0.15))
        XCTAssertEqual(dark.panelRimBottom, .white(0.15))
        XCTAssertEqual(dark.panelRimTop, dark.panelRimBottom,
                       "深色描边必须上下同值，否则就不再是改造前那圈均匀描边")
        XCTAssertEqual(dark.panelRimHighlighted, .white(0.45))
        XCTAssertEqual(dark.panelRimLineWidth, 0.5)
        XCTAssertEqual(dark.panelRimHighlightedLineWidth, 1)
    }

    // 任务条 + 胶囊：black 0.35 / r15 / y8；抽屉 + 两个弹窗：black 0.35 / r12 / y5。
    func testDarkShadowsMatchLegacyLiterals() {
        XCTAssertEqual(dark.stripShadow, DockShadow(tint: .black(0.35), radius: 15, y: 8))
        XCTAssertEqual(dark.popupShadow, DockShadow(tint: .black(0.35), radius: 12, y: 5))
        XCTAssertEqual(dark.iconShadow, DockShadow(tint: .black(0.22), radius: 3, y: 1))
        XCTAssertEqual(dark.tooltipShadow, DockShadow(tint: .black(0.32), radius: 6, y: 2))
        XCTAssertEqual(dark.carrierShadow, DockShadow(tint: .black(0.35), radius: 8, y: 4))
    }

    func testDarkPanelMaterialIsPopover() {
        XCTAssertEqual(dark.panelMaterial, .popover)
    }

    /// 厚度层是 2026-07-30 第二轮新增的。深色必须**整层不画**——不是"画一层全透明的"，
    /// 而是 `drawsPanelThickness == false` 让它根本不进视图树（`.blur(radius: 0)` 仍可能
    /// 触发离屏渲染，多一层就可能破坏深色的逐像素冻结）。
    func testDarkDrawsNoThicknessLayer() {
        XCTAssertFalse(dark.drawsPanelThickness)
        XCTAssertEqual(dark.panelInnerHighlight, .white(0))
        XCTAssertEqual(dark.panelInnerHighlightWidth, 0)
        XCTAssertEqual(dark.panelInnerHighlightBlur, 0)
        XCTAssertEqual(dark.panelInnerShadow, .black(0))
        XCTAssertEqual(dark.panelInnerShadowWidth, 0)
        XCTAssertEqual(dark.panelInnerShadowBlur, 0)
    }

    /// 背景提饱和的**候选值**（默认不生效，靠 `DOCK_PANEL_SATURATION` 开）。
    /// 2026-07-30 实测这条路可行——`.saturation` 作用在合成结果上，模糊保留；
    /// 而 `.opacity` 是死路（露出没模糊的原始桌面），别再拿它当通透度旋钮。
    func testBackdropSaturationCandidate() {
        XCTAssertEqual(dark.panelBackdropSaturation, 1.0, "深色连候选都是恒等")
        XCTAssertGreaterThan(light.panelBackdropSaturation, 1.0, "浅色候选要真的提饱和")
        XCTAssertLessThanOrEqual(light.panelBackdropSaturation, 2.0, "别把实验用的极端值写进表")
    }

    /// 厚度层的**候选值**成立（同样默认不生效，靠 `DOCK_PANEL_THICKNESS=1` 开）。
    func testLightThicknessCandidateIsWellFormed() {
        XCTAssertTrue(light.drawsPanelThickness, "候选值本身要构成一个能画的配置")
        XCTAssertEqual(light.panelInnerHighlight.base, .white, "上内沿是亮线")
        XCTAssertEqual(light.panelInnerShadow.base, .black, "下内沿是暗收")
        XCTAssertGreaterThan(light.panelInnerHighlightWidth, 0)
        XCTAssertGreaterThan(light.panelInnerShadowWidth, 0)
    }

    /// 运行小圆点在两套外观里都必须真的看得见。图标不再按状态淡化（owner 2026-08-02），
    /// 这颗点就成了「应用还在不在」的**唯一**信号——浅色下曾经是白点画在浅玻璃上、等于没有。
    func testRunningDotIsVisibleInBothAppearances() {
        XCTAssertEqual(dark.runningDot.base, .white, "深底上是亮点")
        XCTAssertEqual(light.runningDot.base, .black, "浅底上必须反过来用暗点")
        for (name, tokens) in [("dark", dark), ("light", light)] {
            XCTAssertGreaterThan(tokens.runningDot.opacity, 0.3, "\(name)：运行点太淡就等于没有")
        }
    }

    /// 「要画」需要颜色和线宽同时成立：任一为 0 都等于看不见，此时就不该多挂一层。
    func testThicknessGateNeedsBothColorAndWidth() {
        let off = DockTint.white(0)
        func gate(_ h: DockTint, _ hw: CGFloat, _ s: DockTint = .black(0), _ sw: CGFloat = 0) -> Bool {
            DockThemeTokens.drawsThickness(highlight: h, highlightWidth: hw, shadow: s, shadowWidth: sw)
        }
        XCTAssertFalse(gate(off, 0), "全 0 → 不画")
        XCTAssertFalse(gate(.white(0.5), 0), "有颜色但线宽 0 → 不画")
        XCTAssertFalse(gate(off, 2), "有线宽但全透明 → 不画")
        XCTAssertTrue(gate(.white(0.5), 2), "两者都有 → 画")
        XCTAssertTrue(gate(off, 0, .black(0.06), 2), "只有下内沿暗收也算要画")
    }

    // MARK: - 三个开关：默认必须是「owner 已认可的观感」

    /// 这一组是本轮的核心约束。2026-07-30 出过一次事故：提饱和与厚度层默认生效，
    /// owner 眼前的观感在他不知情的情况下偏离了他点过头的那版，是他自己发现的。
    /// **未验收的效果一律 opt-in**，这几条断言就是那条规矩的机械保证。
    func testAllEffectsAreOffByDefault() {
        let empty: [String: String] = [:]
        XCTAssertEqual(DockEffectSwitches.saturation(from: empty, candidate: 1.25), 1.0,
                       "没设环境变量 → 不提饱和")
        XCTAssertFalse(DockEffectSwitches.thicknessEnabled(from: empty), "没设环境变量 → 不画厚度层")
        XCTAssertEqual(DockPanelMaterial.resolved(from: empty, fallback: .popover), .popover,
                       "没设环境变量 → 用 token 里的材质")
    }

    func testSaturationSwitch() {
        func s(_ raw: String) -> Double {
            DockEffectSwitches.saturation(from: ["DOCK_PANEL_SATURATION": raw], candidate: 1.25)
        }
        XCTAssertEqual(s("1.4"), 1.4, accuracy: 0.0001, "数字就是倍数本身")
        XCTAssertEqual(s(" 1.4 "), 1.4, accuracy: 0.0001, "两端空白要吃掉")
        XCTAssertEqual(s("candidate"), 1.25, accuracy: 0.0001, "candidate = 用表里的候选值")
        XCTAssertEqual(s("CANDIDATE"), 1.25, accuracy: 0.0001, "大小写不敏感")
        XCTAssertEqual(s("1"), 1.0, accuracy: 0.0001, "1 就是不提饱和，不是「开」")
        for bad in ["", "  ", "abc", "0", "-2", "99"] {
            XCTAssertEqual(s(bad), 1.0, accuracy: 0.0001, "非法值 \"\(bad)\" 必须回落到不加滤镜")
        }
    }

    func testThicknessSwitch() {
        func t(_ raw: String) -> Bool {
            DockEffectSwitches.thicknessEnabled(from: ["DOCK_PANEL_THICKNESS": raw])
        }
        XCTAssertTrue(t("1"))
        XCTAssertTrue(t(" 1 "), "两端空白要吃掉")
        for off in ["0", "", "true", "yes", "2", "on"] {
            XCTAssertFalse(t(off), "只认 1；\"\(off)\" 一律当关")
        }
    }

    // MARK: - 材质环境覆盖（调参用，不能崩）

    func testMaterialOverrideParsesKnownNames() {
        for material in DockPanelMaterial.all {
            let env = ["DOCK_PANEL_MATERIAL": "\(material)"]
            XCTAssertEqual(DockPanelMaterial.resolved(from: env, fallback: .popover), material)
        }
    }

    func testMaterialOverrideIsCaseInsensitiveAndTrimmed() {
        XCTAssertEqual(DockPanelMaterial.resolved(from: ["DOCK_PANEL_MATERIAL": "HUDWindow"], fallback: .popover),
                       .hudWindow)
        XCTAssertEqual(DockPanelMaterial.resolved(from: ["DOCK_PANEL_MATERIAL": "  sidebar \n"], fallback: .popover),
                       .sidebar)
    }

    /// 手滑打错名字不该让应用起不来，也不该静默变成别的材质——回落到 token 原值。
    func testMaterialOverrideFallsBackOnUnknownOrEmpty() {
        for raw in ["", "   ", "nope", "popver", "0"] {
            XCTAssertEqual(DockPanelMaterial.resolved(from: ["DOCK_PANEL_MATERIAL": raw], fallback: .menu), .menu,
                           "非法值 \"\(raw)\" 必须回落")
        }
        XCTAssertEqual(DockPanelMaterial.resolved(from: [:], fallback: .menu), .menu, "没设环境变量就用 token 值")
    }

    /// 候选表要覆盖枚举全部 case——漏一个，对照表就少拍一张，owner 可能正好错过想要的那个。
    func testMaterialAllCoversEveryCase() {
        XCTAssertEqual(Set(DockPanelMaterial.all).count, DockPanelMaterial.all.count, "候选表不能重复")
        XCTAssertTrue(DockPanelMaterial.all.contains(.popover))
        XCTAssertEqual(DockPanelMaterial.all.count, 14, "系统材质候选共 14 种；新增 case 时同步这里")
    }

    // 标题胶囊：底 white 0.08 / 悬停 0.14；描边渐变上 white 0.15（悬停 0.25）→ 下 white 0.02。
    func testDarkChipPillMatchesLegacyLiterals() {
        XCTAssertEqual(dark.chipPillFill, DockTintPair(normal: .white(0.08), emphasized: .white(0.14)))
        XCTAssertEqual(dark.chipPillRimTop, DockTintPair(normal: .white(0.15), emphasized: .white(0.25)))
        XCTAssertEqual(dark.chipPillRimBottom, .white(0.02))
    }

    // 文字：标题 0.9 / 非前台 0.6，悬停名 0.85，副标题 0.65。
    func testDarkLabelsMatchLegacyLiterals() {
        XCTAssertEqual(dark.labelActive, .white(0.9))
        XCTAssertEqual(dark.labelInactive, .white(0.6))
        XCTAssertEqual(dark.labelHover, .white(0.85))
        XCTAssertEqual(dark.labelSubtitle, .white(0.65))
    }

    func testDarkIndicatorsMatchLegacyLiterals() {
        XCTAssertEqual(dark.runningDot, .white(0.85))
        XCTAssertEqual(dark.zoneDivider, .white(0.18))
    }

    // 中转格：底板 0.12 → 命中 0.28，描边 0.18 → 0.28 命中 0.4，图标 0.9，命中光晕 0.25。
    func testDarkShelfChipMatchesLegacyLiterals() {
        XCTAssertEqual(dark.shelfPlateFill, DockTintPair(normal: .white(0.12), emphasized: .white(0.28)))
        XCTAssertEqual(dark.shelfPlateRim, DockTintPair(normal: .white(0.18), emphasized: .white(0.4)))
        XCTAssertEqual(dark.shelfGlyph, .white(0.9))
        XCTAssertEqual(dark.shelfDropGlow, .white(0.25))
    }

    func testDarkCapsuleMatchesLegacyLiterals() {
        XCTAssertEqual(dark.capsuleGlyph, .white(0.72))
        XCTAssertEqual(dark.capsuleStashGlow, .white(0.18))
    }

    func testDarkFolderChipMatchesLegacyLiterals() {
        XCTAssertEqual(dark.folderDropRing, .white(0.9))
        XCTAssertEqual(dark.folderThumbHairline, .white(0.35))
    }

    func testDarkPopupMatchesLegacyLiterals() {
        XCTAssertEqual(dark.popupCellLabel, .white(0.9))
        XCTAssertEqual(dark.popupCellHover, .white(0.12))
        XCTAssertEqual(dark.popupPrimaryText, .white(0.8))
        XCTAssertEqual(dark.popupSecondaryText, .white(0.5))
        XCTAssertEqual(dark.backChipFill, .white(0.16))
        XCTAssertEqual(dark.backChipRim, .white(0.2))
        XCTAssertEqual(dark.backChipGlyph, .white(0.85))
    }

    // tooltip 是唯一「深色加黑、浅色加白」的地方（它叠在 .ultraThinMaterial 上）。
    func testDarkTooltipMatchesLegacyLiterals() {
        XCTAssertEqual(dark.tooltipTint, .black(0.28))
        XCTAssertEqual(dark.tooltipRim, .white(0.18))
        XCTAssertEqual(dark.tooltipText, .white(0.94))
    }

    /// 上面的逐组断言覆盖了 `DockThemeTokens` 的**全部** 38 个字段（新增字段时请一并补进对应组）。
    /// 这条只守一件事：两套不能退化成同一套，否则等于没做适配。
    func testDarkAndLightAreDistinct() {
        XCTAssertNotEqual(dark, light)
    }

    // MARK: - 浅色的结构性约束（数值可调，这些性质不可破）

    /// 浅色阴影必须收在 shadowPadding（20pt）预算内。
    /// 超了就会在面板透明边处被硬切成一道齐口直边——正是用户报的「阴影还会延伸溢出」。
    func testLightShadowsFitInsideShadowPaddingBudget() {
        XCTAssertLessThanOrEqual(light.stripShadow.verticalExtent, shadowPadding)
        XCTAssertLessThanOrEqual(light.popupShadow.verticalExtent, shadowPadding)
        XCTAssertLessThanOrEqual(light.carrierShadow.verticalExtent, shadowPadding)
    }

    /// 已知遗留：深色任务条阴影 15 + 8 = 23 > 20，被裁掉 3pt。
    /// 修它要改深色观感，违反本轮「深色冻结」，已单独记待办。这条测试把现状钉住，
    /// 免得以后有人以为深色也在预算内、或者悄悄改了深色数值。
    func testDarkStripShadowStillExceedsBudgetKnownIssue() {
        XCTAssertEqual(dark.stripShadow.verticalExtent, 23)
        XCTAssertGreaterThan(dark.stripShadow.verticalExtent, shadowPadding)
        XCTAssertLessThanOrEqual(dark.popupShadow.verticalExtent, shadowPadding,
                                 "抽屉/弹窗的 12+5=17 一直在预算内，别把它也带出界")
    }

    /// 浅色的前景必须是**加黑**而不是加白：浅色玻璃上加白等于消失，只剩描边孤零零留着，
    /// 每张卡就变成一个空心方格——这正是用户抱怨的「周围有很明显的方格」。
    func testLightForegroundsAreDarkTinted() {
        let mustBeBlack: [(String, DockTint)] = [
            ("labelActive", light.labelActive),
            ("labelInactive", light.labelInactive),
            ("labelHover", light.labelHover),
            ("labelSubtitle", light.labelSubtitle),
            ("runningDot", light.runningDot),
            ("zoneDivider", light.zoneDivider),
            ("chipPillFill.normal", light.chipPillFill.normal),
            ("chipPillFill.emphasized", light.chipPillFill.emphasized),
            ("shelfPlateFill.normal", light.shelfPlateFill.normal),
            ("shelfGlyph", light.shelfGlyph),
            ("capsuleGlyph", light.capsuleGlyph),
            ("folderDropRing", light.folderDropRing),
            ("popupCellLabel", light.popupCellLabel),
            ("popupCellHover", light.popupCellHover),
            ("popupSecondaryText", light.popupSecondaryText),
            ("backChipFill", light.backChipFill),
            ("tooltipText", light.tooltipText),
        ]
        for (name, tint) in mustBeBlack {
            XCTAssertEqual(tint.base, .black, "浅色的 \(name) 必须加黑，加白在浅玻璃上会消失")
        }
    }

    /// 面板描边在浅色下是「上沿亮（白高光）+ 下沿暗（黑细线）」——苹果原生玻璃的打光方向。
    /// 改造前那圈均匀白描边在浅色下就是用户看到的灰框。
    func testLightPanelRimIsBrightTopDarkBottom() {
        XCTAssertEqual(light.panelRimTop.base, .white)
        XCTAssertEqual(light.panelRimBottom.base, .black)
        XCTAssertGreaterThan(light.panelRimTop.opacity, light.panelRimBottom.opacity)
    }

    /// tooltip 在浅色下要反过来加白提亮（它是唯一有这个反转的地方）。
    func testLightTooltipTintIsBright() {
        XCTAssertEqual(light.tooltipTint.base, .white)
        XCTAssertEqual(dark.tooltipTint.base, .black)
    }

    /// 所有不透明度必须在 0…1 之内（手调时容易顺手写超）。
    func testAllOpacitiesAreInRange() {
        for tokens in [dark, light] {
            for tint in tokens.allTints {
                XCTAssertTrue((0...1).contains(tint.opacity),
                              "不透明度越界：\(tint)")
            }
        }
    }

    // MARK: - 外观档位 → NSAppearance

    /// 这个映射是整条「浅色 / 深色」功能的唯一执行点：设到 `NSApp.appearance` 上，
    /// 主题色、毛玻璃材质、菜单、之后新建的面板全跟着它走。
    func testAppearanceModeMapsToNSAppearance() {
        XCTAssertNil(AppearanceMode.system.nsAppearance, "跟随系统 = 交还给系统，不能设成 .aqua")
        XCTAssertEqual(AppearanceMode.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppearanceMode.dark.nsAppearance?.name, .darkAqua)
    }
}

// MARK: - 测试辅助

private extension DockThemeTokens {
    /// 遍历用：本表里所有着色值（含阴影自带的着色）。
    var allTints: [DockTint] {
        [panelRimTop, panelRimBottom, panelRimHighlighted,
         panelInnerHighlight, panelInnerShadow,
         stripShadow.tint, popupShadow.tint,
         chipPillFill.normal, chipPillFill.emphasized,
         chipPillRimTop.normal, chipPillRimTop.emphasized, chipPillRimBottom,
         labelActive, labelInactive, labelHover, labelSubtitle,
         runningDot, zoneDivider,
         iconShadow.tint,
         shelfPlateFill.normal, shelfPlateFill.emphasized,
         shelfPlateRim.normal, shelfPlateRim.emphasized,
         shelfGlyph, shelfDropGlow,
         capsuleGlyph, capsuleStashGlow,
         folderDropRing, folderThumbHairline,
         popupCellLabel, popupCellHover, popupPrimaryText, popupSecondaryText,
         backChipFill, backChipRim, backChipGlyph,
         tooltipTint, tooltipRim, tooltipText, tooltipShadow.tint,
         carrierShadow.tint]
    }
}
