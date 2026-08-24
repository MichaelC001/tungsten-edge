import XCTest

final class FeedbackSubmitterTests: XCTestCase {
    private func okResponse(_ status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: WebsiteFeedbackSubmitter.endpointURL,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func fullDraft() -> FeedbackDraft {
        FeedbackDraft(
            message: "任务条很好用",
            contact: "me@example.com",
            appVersion: "版本 0.9.5 (117)",
            macosVersion: "macOS 15.5",
            lang: "zh"
        )
    }

    // MARK: 请求形状

    func testRequestCarriesHeaderTimeoutAndExactlyTheDisclosedFields() async throws {
        var captured: URLRequest?
        let submitter = WebsiteFeedbackSubmitter { request in
            captured = request
            return (Data("{}".utf8), self.okResponse())
        }

        try await submitter.submit(fullDraft())

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url, WebsiteFeedbackSubmitter.endpointURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, WebsiteFeedbackSubmitter.requestTimeout)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Tungsten-Client"), "app")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            ["appVersion", "contact", "lang", "macosVersion", "message"],
            "body 恰好是界面披露的五个字段"
        )
        XCTAssertEqual(object["message"] as? String, "任务条很好用")
    }

    func testNilOptionalFieldsAreOmittedNeverPadded() async throws {
        var captured: URLRequest?
        let submitter = WebsiteFeedbackSubmitter { request in
            captured = request
            return (Data(), self.okResponse(201))
        }

        try await submitter.submit(FeedbackDraft(
            message: "hi", contact: nil, appVersion: nil, macosVersion: nil, lang: "en"
        ))

        let body = try XCTUnwrap(captured?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["lang", "message"], "没填的字段整个省略，不发空值")
    }

    // MARK: 只有 2xx 算成功

    func testNon2xxThrowsHTTPStatus() async {
        let submitter = WebsiteFeedbackSubmitter { _ in (Data(), self.okResponse(429)) }
        do {
            try await submitter.submit(fullDraft())
            XCTFail("429 必须抛错")
        } catch let error as FeedbackError {
            XCTAssertEqual(error, .httpStatus(429))
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    func testNonHTTPResponseThrowsInvalidResponse() async {
        let submitter = WebsiteFeedbackSubmitter { _ in
            (Data(), URLResponse(url: WebsiteFeedbackSubmitter.endpointURL, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
        do {
            try await submitter.submit(fullDraft())
            XCTFail("非 HTTP 响应必须抛错")
        } catch let error as FeedbackError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    // MARK: 纯校验

    func testDraftCheckBoundaries() {
        XCTAssertEqual(FeedbackDraftCheck.validate(message: "  \n ", contact: ""), .emptyMessage)
        XCTAssertNil(FeedbackDraftCheck.validate(message: String(repeating: "字", count: 2000), contact: ""))
        XCTAssertEqual(
            FeedbackDraftCheck.validate(message: String(repeating: "字", count: 2001), contact: ""),
            .messageTooLong
        )
        XCTAssertNil(FeedbackDraftCheck.validate(message: "ok", contact: String(repeating: "c", count: 120)))
        XCTAssertEqual(
            FeedbackDraftCheck.validate(message: "ok", contact: String(repeating: "c", count: 121)),
            .contactTooLong
        )
    }

    // MARK: 在飞守卫与文案

    func testSubmitStateGuardsReentry() {
        var state = FeedbackSubmitState()
        XCTAssertTrue(state.begin())
        XCTAssertFalse(state.begin(), "在飞时不允许再次提交")
        XCTAssertFalse(state.presentation.isEnabled)
        state.finish()
        XCTAssertTrue(state.begin())
    }

    func testAlertContentSemantics() {
        XCTAssertTrue(FeedbackAlertContent.sent.didSend)
        XCTAssertFalse(FeedbackAlertContent.failure.didSend)
        XCTAssertTrue(FeedbackAlertContent.failure.isWarning)
        XCTAssertTrue(FeedbackAlertContent(rejection: .emptyMessage).isWarning)
        XCTAssertFalse(FeedbackAlertContent(rejection: .messageTooLong).didSend)
    }
}
