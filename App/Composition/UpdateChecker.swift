import Foundation

struct AppVersion: Comparable, Equatable {
    private let components: [Int]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }

        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var parsed: [Int] = []
        parsed.reserveCapacity(parts.count)
        for part in parts {
            guard !part.isEmpty,
                  part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(part) else { return nil }
            parsed.append(number)
        }

        while parsed.count > 1, parsed.last == 0 {
            parsed.removeLast()
        }
        components = parsed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

enum UpdateCheckOutcome: Equatable {
    case updateAvailable(currentVersion: String, latestVersion: String, releaseURL: URL)
    case upToDate(currentVersion: String, latestVersion: String)
}

protocol UpdateChecking {
    func check(currentVersion: String) async throws -> UpdateCheckOutcome
}

typealias UpdateRequestLoader = (URLRequest) async throws -> (Data, URLResponse)

final class GitHubUpdateChecker: UpdateChecking {
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/moonbai-studio/tungsten-edge/releases/latest")!
    static let requestTimeout: TimeInterval = 10

    private let loader: UpdateRequestLoader

    init(session: URLSession = .shared) {
        loader = { request in
            try await session.data(for: request)
        }
    }

    init(loader: @escaping UpdateRequestLoader) {
        self.loader = loader
    }

    func check(currentVersion: String) async throws -> UpdateCheckOutcome {
        guard let installedVersion = AppVersion(currentVersion) else {
            throw UpdateCheckError.invalidCurrentVersion
        }

        var request = URLRequest(url: Self.latestReleaseAPIURL, timeoutInterval: Self.requestTimeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Tungsten-Edge/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await loader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.httpStatus(httpResponse.statusCode)
        }

        let release = try JSONDecoder().decode(LatestRelease.self, from: data)
        guard let latestVersion = AppVersion(release.tagName) else {
            throw UpdateCheckError.invalidLatestVersion
        }

        if installedVersion < latestVersion {
            return .updateAvailable(
                currentVersion: currentVersion,
                latestVersion: release.tagName,
                releaseURL: release.htmlURL
            )
        }
        return .upToDate(currentVersion: currentVersion, latestVersion: release.tagName)
    }
}

private struct LatestRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

enum UpdateCheckError: LocalizedError, Equatable {
    case invalidCurrentVersion
    case invalidLatestVersion
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion:
            return String(localized: "Couldn’t read the current version number.")
        case .invalidLatestVersion:
            return String(localized: "The latest version number is not in a valid format.")
        case .invalidResponse:
            return String(localized: "The update server returned an invalid response.")
        case .httpStatus(let status):
            return String(format: String(localized: "The update server returned status code %d."), status)
        }
    }
}

struct UpdateCheckMenuPresentation: Equatable {
    let title: String
    let isEnabled: Bool
}

struct UpdateCheckMenuState {
    private(set) var isCheckingUpdates = false

    var presentation: UpdateCheckMenuPresentation {
        if isCheckingUpdates {
            return UpdateCheckMenuPresentation(title: String(localized: "Checking for Updates…"), isEnabled: false)
        }
        return UpdateCheckMenuPresentation(title: String(localized: "Check for Updates…"), isEnabled: true)
    }

    mutating func begin() -> Bool {
        guard !isCheckingUpdates else { return false }
        isCheckingUpdates = true
        return true
    }

    mutating func finish() {
        isCheckingUpdates = false
    }
}

/// 检查更新结果的**文案单一来源**。状态栏菜单渲染成 `NSAlert`、设置窗口渲染成附着式
/// SwiftUI alert，两处的措辞必须一致——各写一份迟早会漂。纯值类型，可单测。
struct UpdateCheckAlertContent: Equatable {
    let title: String
    let message: String
    /// 非 nil 时展示一个打开链接的按钮；nil 时只有「好」。
    let openButtonTitle: String?
    let openURL: URL?
    /// 只有「查不到」是警告，查到结果（无论有没有新版）都是普通信息。
    let isWarning: Bool

    init(
        title: String,
        message: String,
        openButtonTitle: String? = nil,
        openURL: URL? = nil,
        isWarning: Bool = false
    ) {
        self.title = title
        self.message = message
        self.openButtonTitle = openButtonTitle
        self.openURL = openURL
        self.isWarning = isWarning
    }

    /// 官方下载页。**每一个用户可见的「去下载」都必须指向这里，不能指向 GitHub release 页**
    /// ——2026-08-13 起 GitHub 只发源码，release 页面上不再有安装包，指过去就是一个空页面。
    /// 版本检测仍然走 GitHub API（tag 还在，可靠且免费），变的只是下载去向。
    static let downloadPageURL = URL(string: "https://tungstenedge.app")!

    init(outcome: UpdateCheckOutcome) {
        switch outcome {
        case let .updateAvailable(currentVersion, latestVersion, _):
            // 这里**故意不用** outcome 里的 releaseURL：那是 GitHub release 页，已经没有安装包了。
            self.init(
                title: String(format: String(localized: "Version %@ Is Available"), latestVersion),
                message: String(format: String(localized: "You have %@. Tungsten Edge still has to be downloaded and installed manually."), currentVersion),
                openButtonTitle: String(localized: "Download"),
                openURL: Self.downloadPageURL
            )
        case let .upToDate(currentVersion, latestVersion):
            self.init(
                title: String(localized: "You’re Up to Date"),
                message: String(format: String(localized: "You have %@; the latest release is %@."), currentVersion, latestVersion)
            )
        }
    }

    static let failure = UpdateCheckAlertContent(
        title: String(localized: "Can’t Check for Updates Right Now"),
        message: String(localized: "Check your network connection and try again, or open the download page directly."),
        openButtonTitle: String(localized: "Open Website"),
        openURL: UpdateCheckAlertContent.downloadPageURL,
        isWarning: true
    )
}
