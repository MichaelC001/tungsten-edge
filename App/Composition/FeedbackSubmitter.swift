import Foundation

/// 反馈草稿的纯校验。上限与服务端 `functions/_lib/feedback-policy.js` 保持同一个数——
/// 客户端先挡明显超限的，省一次没意义的往返；真校验永远在服务端。
enum FeedbackDraftCheck {
    static let messageMaximum = 2000
    static let contactMaximum = 120

    enum Rejection: Equatable {
        case emptyMessage
        case messageTooLong
        case contactTooLong
    }

    static func validate(message: String, contact: String) -> Rejection? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedMessage.isEmpty { return .emptyMessage }
        if trimmedMessage.count > messageMaximum { return .messageTooLong }
        if contact.trimmingCharacters(in: .whitespacesAndNewlines).count > contactMaximum {
            return .contactTooLong
        }
        return nil
    }
}

/// 反馈类型（2026-08-24「模板引导」）：radio 三选一 + 随类型变的引导文字。
/// 类型**并入 message 开头**（见 `FeedbackComposition`），不加第六个字段——
/// 「只发送……五个字段」的披露承诺因此不用改，服务端/控制台/邮件也全不用动。
enum FeedbackCategory: String, CaseIterable {
    case bug
    case suggestion
    case other

    var displayName: String {
        switch self {
        case .bug: return String(localized: "Bug Report")
        case .suggestion: return String(localized: "Feature Suggestion")
        case .other: return String(localized: "Other")
        }
    }

    /// 输入框为空时叠显的引导文字（随类型变，overlay 不占布局）。
    var placeholder: String {
        switch self {
        case .bug:
            return String(localized: "What went wrong? What did you do when it happened? Paste any details that might help.")
        case .suggestion:
            return String(localized: "What should Tungsten Edge add or improve? Tell us how you'd use it.")
        case .other:
            return String(localized: "Anything you want to say — write it here.")
        }
    }
}

/// 正文组装的唯一入口：trim 后为空返回 nil，否则「【类型】\n正文」。
/// 长度校验必须跑在组装结果上（`performFeedback` 收到的就是它）——前缀也占
/// 2000 字限额，客户端不挡的话服务端会 400，弹「无法发送」误导用户。
enum FeedbackComposition {
    static func compose(category: FeedbackCategory, message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "【\(category.displayName)】\n\(trimmed)"
    }
}

/// 一次反馈提交的全部内容。**恰好**是设置界面披露的五个字段，一个不多——
/// 「只发送你写的内容、联系方式、App 版本、macOS 版本和界面语言」是写在界面上的承诺。
struct FeedbackDraft: Equatable {
    let message: String
    let contact: String?
    let appVersion: String?
    let macosVersion: String?
    let lang: String
}

protocol FeedbackSubmitting {
    func submit(_ draft: FeedbackDraft) async throws
}

typealias FeedbackRequestLoader = (URLRequest) async throws -> (Data, URLResponse)

/// 提交到官网的 `/api/feedback`（Cloudflare Pages Function → D1，owner 在本机控制台看）。
///
/// 三条承重规则与订阅完全一致（权威注释在 `WebsiteSubscriptionSubmitter`）：
/// **只有 2xx 算成功**；`X-Tungsten-Client: app` **不是安全校验**（只是让无 Origin 的
/// 原生请求走得通）；body 恰好是披露的五个字段。
final class WebsiteFeedbackSubmitter: FeedbackSubmitting {
    static let endpointURL = URL(string: "https://tungstenedge.app/api/feedback")!
    static let requestTimeout: TimeInterval = 15

    private let loader: FeedbackRequestLoader

    init(session: URLSession = .shared) {
        loader = { request in
            try await session.data(for: request)
        }
    }

    /// 测试注入点：假 loader 验请求内容与各种响应，不碰真网络。
    init(loader: @escaping FeedbackRequestLoader) {
        self.loader = loader
    }

    func submit(_ draft: FeedbackDraft) async throws {
        var request = URLRequest(url: Self.endpointURL, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            WebsiteSubscriptionSubmitter.clientHeaderValue,
            forHTTPHeaderField: WebsiteSubscriptionSubmitter.clientHeaderField
        )

        let body = RequestBody(
            appVersion: draft.appVersion,
            contact: draft.contact,
            lang: draft.lang,
            macosVersion: draft.macosVersion,
            message: draft.message
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(body)

        let (_, response) = try await loader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedbackError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FeedbackError.httpStatus(httpResponse.statusCode)
        }
        // 2xx 即成功：D1-first，服务端已经收下了。响应体只有一句话，不解析。
    }

    private struct RequestBody: Encodable {
        let appVersion: String?
        let contact: String?
        let lang: String
        let macosVersion: String?
        let message: String
    }
}

enum FeedbackError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "The feedback server returned an invalid response.")
        case .httpStatus(let status):
            return String(format: String(localized: "The feedback server returned status code %d."), status)
        }
    }
}

/// 在飞守卫（同订阅的 `SubscriptionSubmitState`）：连点两下不能发两次。
struct FeedbackSubmitState {
    private(set) var isSubmitting = false

    var presentation: FeedbackSubmitPresentation {
        if isSubmitting {
            return FeedbackSubmitPresentation(title: String(localized: "Sending…"), isEnabled: false)
        }
        return FeedbackSubmitPresentation(title: String(localized: "Send"), isEnabled: true)
    }

    mutating func begin() -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        return true
    }

    mutating func finish() {
        isSubmitting = false
    }
}

struct FeedbackSubmitPresentation: Equatable {
    let title: String
    let isEnabled: Bool
}

/// 反馈结果的**文案单一来源**，纯值类型、可单测（同 `SubscriptionAlertContent` 的套路）。
struct FeedbackAlertContent: Equatable {
    let title: String
    let message: String
    let isWarning: Bool
    /// 真送达才 true：调用方据此决定要不要清空输入框。
    let didSend: Bool

    init(title: String, message: String, isWarning: Bool = false, didSend: Bool = false) {
        self.title = title
        self.message = message
        self.isWarning = isWarning
        self.didSend = didSend
    }

    init(rejection: FeedbackDraftCheck.Rejection) {
        switch rejection {
        case .emptyMessage:
            self.init(
                title: String(localized: "Message Is Empty"),
                message: String(localized: "Write something first."),
                isWarning: true
            )
        case .messageTooLong:
            self.init(
                title: String(localized: "Message Is Too Long"),
                message: String(localized: "Keep it under 2000 characters."),
                isWarning: true
            )
        case .contactTooLong:
            self.init(
                title: String(localized: "Contact Is Too Long"),
                message: String(localized: "Keep it under 120 characters."),
                isWarning: true
            )
        }
    }

    static let sent = FeedbackAlertContent(
        title: String(localized: "Feedback Sent"),
        message: String(localized: "Thanks — we read every message."),
        didSend: true
    )

    static let failure = FeedbackAlertContent(
        title: String(localized: "Can’t Send Right Now"),
        message: String(localized: "Check your network connection and try again, or email support@tungstenedge.app."),
        isWarning: true
    )
}
