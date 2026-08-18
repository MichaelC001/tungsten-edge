import XCTest

final class UpdateCheckerTests: XCTestCase {
    func testVersionComparisonAcceptsLeadingVAndPadsMissingSegments() {
        XCTAssertEqual(AppVersion("v0.5"), AppVersion("0.5.0"))
        XCTAssertEqual(AppVersion("V1.2.0.0"), AppVersion("1.2"))
        XCTAssertLessThan(AppVersion("0.5.9")!, AppVersion("0.6")!)
        XCTAssertGreaterThan(AppVersion("1.10")!, AppVersion("1.2.9")!)
    }

    func testVersionComparisonRejectsNonNumericVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("1.2-beta"))
        XCTAssertNil(AppVersion("1.2+3"))
    }

    func testNewerReleaseUsesGitHubReleaseURL() async throws {
        let expectedURL = URL(string: "https://github.com/moonbai-studio/tungsten-edge/releases/tag/v0.6.0")!
        let checker = makeChecker(
            statusCode: 200,
            json: #"{"tag_name":"v0.6.0","html_url":"https://github.com/moonbai-studio/tungsten-edge/releases/tag/v0.6.0"}"#
        )

        let outcome = try await checker.check(currentVersion: "0.5.0")

        XCTAssertEqual(
            outcome,
            .updateAvailable(currentVersion: "0.5.0", latestVersion: "v0.6.0", releaseURL: expectedURL)
        )
    }

    func testEqualOrOlderReleaseIsUpToDate() async throws {
        let equalChecker = makeChecker(
            statusCode: 200,
            json: #"{"tag_name":"v0.5","html_url":"https://github.com/moonbai-studio/tungsten-edge/releases/tag/v0.5.0"}"#
        )
        let olderChecker = makeChecker(
            statusCode: 200,
            json: #"{"tag_name":"v0.4.5","html_url":"https://github.com/moonbai-studio/tungsten-edge/releases/tag/v0.4.5"}"#
        )
        let equalOutcome = try await equalChecker.check(currentVersion: "0.5.0")
        let olderOutcome = try await olderChecker.check(currentVersion: "0.5.0")

        XCTAssertEqual(
            equalOutcome,
            .upToDate(currentVersion: "0.5.0", latestVersion: "v0.5")
        )
        XCTAssertEqual(
            olderOutcome,
            .upToDate(currentVersion: "0.5.0", latestVersion: "v0.4.5")
        )
    }

    func testRequestUsesGitHubHeadersAndTenSecondTimeout() async throws {
        var capturedRequest: URLRequest?
        let checker = GitHubUpdateChecker { request in
            capturedRequest = request
            return self.response(
                statusCode: 200,
                json: #"{"tag_name":"v0.5.0","html_url":"https://github.com/moonbai-studio/tungsten-edge/releases/tag/v0.5.0"}"#
            )
        }

        _ = try await checker.check(currentVersion: "0.5.0")

        XCTAssertEqual(capturedRequest?.url, GitHubUpdateChecker.latestReleaseAPIURL)
        XCTAssertEqual(capturedRequest?.timeoutInterval, GitHubUpdateChecker.requestTimeout)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "User-Agent"), "Tungsten-Edge/0.5.0")
    }

    func testHTTPFailureIsReported() async {
        let checker = makeChecker(statusCode: 503, json: "{}")

        await XCTAssertThrowsErrorAsync(try await checker.check(currentVersion: "0.5.0")) { error in
            XCTAssertEqual(error as? UpdateCheckError, .httpStatus(503))
        }
    }

    func testInvalidJSONAndInvalidTagAreReported() async {
        let invalidJSON = makeChecker(statusCode: 200, json: "not-json")
        let invalidTag = makeChecker(
            statusCode: 200,
            json: #"{"tag_name":"v0.6.0-beta","html_url":"https://github.com/moonbai-studio/tungsten-edge/releases/tag/v0.6.0-beta"}"#
        )

        await XCTAssertThrowsErrorAsync(try await invalidJSON.check(currentVersion: "0.5.0")) { error in
            XCTAssertTrue(error is DecodingError)
        }
        await XCTAssertThrowsErrorAsync(try await invalidTag.check(currentVersion: "0.5.0")) { error in
            XCTAssertEqual(error as? UpdateCheckError, .invalidLatestVersion)
        }
    }

    func testTimeoutPassesThroughAndFallbackURLIsStable() async {
        let checker = GitHubUpdateChecker { _ in throw URLError(.timedOut) }

        await XCTAssertThrowsErrorAsync(try await checker.check(currentVersion: "0.5.0")) { error in
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(
            UpdateCheckAlertContent.downloadPageURL,
            URL(string: "https://tungstenedge.app")
        )
        XCTAssertEqual(UpdateCheckAlertContent.failure.openURL, UpdateCheckAlertContent.downloadPageURL)
    }

    /// 2026-08-13 分发切换的回归锁：GitHub 只发源码，release 页面上没有安装包了。
    /// 版本检测照旧读 GitHub API（所以 outcome 里仍然带着 releaseURL），但**用户点的那个按钮
    /// 必须落到官网**——把它改回 releaseURL 就是把所有老用户的更新路径送进一个空页面。
    func testUpdateAvailableAlertSendsUserToWebsiteNotGitHubReleasePage() {
        let releaseURL = URL(string: "https://github.com/moonbai-studio/tungsten-edge/releases/tag/v0.9.0")!
        let content = UpdateCheckAlertContent(
            outcome: .updateAvailable(currentVersion: "0.8.0", latestVersion: "v0.9.0", releaseURL: releaseURL)
        )

        XCTAssertEqual(content.openURL, UpdateCheckAlertContent.downloadPageURL)
        XCTAssertNotEqual(content.openURL, releaseURL)
        XCTAssertEqual(content.openButtonTitle, String(localized: "Download"))
    }

    func testMenuStateRejectsDuplicateChecksAndRestoresAfterFinish() {
        var state = UpdateCheckMenuState()

        XCTAssertTrue(state.begin())
        XCTAssertFalse(state.begin())
        XCTAssertEqual(state.presentation, UpdateCheckMenuPresentation(title: String(localized: "Checking for Updates…"), isEnabled: false))

        state.finish()
        XCTAssertEqual(state.presentation, UpdateCheckMenuPresentation(title: String(localized: "Check for Updates…"), isEnabled: true))
        XCTAssertTrue(state.begin())
    }

    private func makeChecker(statusCode: Int, json: String) -> GitHubUpdateChecker {
        GitHubUpdateChecker { _ in
            self.response(statusCode: statusCode, json: json)
        }
    }

    private func response(statusCode: Int, json: String) -> (Data, URLResponse) {
        let url = GitHubUpdateChecker.latestReleaseAPIURL
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), response)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
