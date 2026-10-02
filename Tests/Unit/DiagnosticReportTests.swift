import XCTest

final class DiagnosticReportTests: XCTestCase {
    private func report() -> DiagnosticReport {
        DiagnosticReport(
            appVersion: "0.13.3 (140)",
            systemVersion: "Version 27.0 (Build 26A428)",
            hardwareModel: "Mac17,9",
            language: "zh-Hans",
            appearance: "dark (follows system)",
            reduceTransparency: false,
            increaseContrast: true,
            displays: ["1512x982@2x", "2560x1440@1x"],
            glassPath: "variant 3",
            glassTint: "0.4",
            glassVariants: [
                .init(label: "0", reading: "L0.85 N0.40 R-27.00 B5.00 K77"),
                .init(label: "3", reading: nil),
            ],
            glassPanels: [.init(label: "1512x94", reading: "L0.00 N0.00 R-29.88 B5.42 K77")]
        )
    }

    func testTextListsEveryFieldOnItsOwnLine() {
        XCTAssertEqual(report().text, """
        Tungsten Edge diagnostics
        app: 0.13.3 (140)
        macOS: Version 27.0 (Build 26A428) · Mac17,9
        language: zh-Hans
        appearance: dark (follows system)
        accessibility: reduceTransparency=0 increaseContrast=1
        displays: 1512x982@2x, 2560x1440@1x
        glass path: variant 3
        glass tint: 0.4
        glass variants: 0=L0.85 N0.40 R-27.00 B5.00 K77 | 3=unreadable
        glass panels: 1512x94=L0.00 N0.00 R-29.88 B5.42 K77
        """)
    }

    /// A frosted (macOS 12–25) or unreadable system must still produce a complete report.
    func testMissingValuesAreSpelledOut() {
        var empty = report()
        empty.appVersion = nil
        empty.hardwareModel = nil
        empty.glassTint = nil
        empty.displays = []
        empty.glassVariants = []
        empty.glassPanels = []
        let lines = empty.text.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("app: unknown"))
        XCTAssertTrue(lines.contains("macOS: Version 27.0 (Build 26A428)"))
        XCTAssertTrue(lines.contains("displays: none"))
        XCTAssertTrue(lines.contains("glass tint: unset"))
        XCTAssertTrue(lines.contains("glass variants: none"))
        XCTAssertTrue(lines.contains("glass panels: none"))
    }
}
