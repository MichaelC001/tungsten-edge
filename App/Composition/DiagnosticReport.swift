import Foundation

/// Plain-text diagnostics the user copies from Settings ▸ About and pastes to us.
///
/// It is data for us, like a log line: the labels stay English in every UI language. Nothing
/// here is sent anywhere — the feedback form's disclosed fields are unchanged.
struct DiagnosticReport: Equatable {
    struct GlassReading: Equatable {
        let label: String
        /// `TEDockGlassDescribeLayer`'s output; nil when no glass filter could be read.
        let reading: String?
    }

    var appVersion: String?
    var systemVersion: String
    var hardwareModel: String?
    var language: String
    var appearance: String
    var reduceTransparency: Bool
    var increaseContrast: Bool
    var displays: [String]
    var glassPath: String
    var glassTint: String?
    /// What each private variant number resolves to on this system.
    var glassVariants: [GlassReading]
    /// What the live glass panels actually carry.
    var glassPanels: [GlassReading]

    var text: String {
        let system = [systemVersion, hardwareModel].compactMap { $0 }.joined(separator: " · ")
        return [
            "Tungsten Edge diagnostics",
            "app: \(appVersion ?? "unknown")",
            "macOS: \(system)",
            "language: \(language)",
            "appearance: \(appearance)",
            "accessibility: reduceTransparency=\(reduceTransparency ? 1 : 0) increaseContrast=\(increaseContrast ? 1 : 0)",
            "displays: \(Self.joined(displays, separator: ", "))",
            "glass path: \(glassPath)",
            "glass tint: \(glassTint ?? "unset")",
            "glass variants: \(Self.joined(glassVariants.map(Self.line), separator: " | "))",
            "glass panels: \(Self.joined(glassPanels.map(Self.line), separator: " | "))",
        ].joined(separator: "\n")
    }

    private static func line(_ reading: GlassReading) -> String {
        "\(reading.label)=\(reading.reading ?? "unreadable")"
    }

    private static func joined(_ items: [String], separator: String) -> String {
        items.isEmpty ? "none" : items.joined(separator: separator)
    }
}
