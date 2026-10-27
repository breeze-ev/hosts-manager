import AppKit
import Combine
import CoreServices
import CryptoKit
import Foundation
import SwiftUI

nonisolated struct AppVersion: Comparable, Equatable, Sendable {
    let components: [Int]
    let prerelease: [String]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        if let buildMetadataIndex = value.firstIndex(of: "+") {
            value = String(value[..<buildMetadataIndex])
        }

        let core: String
        if let prereleaseIndex = value.firstIndex(of: "-") {
            core = String(value[..<prereleaseIndex])
            let suffix = String(value[value.index(after: prereleaseIndex)...])
            let identifiers = suffix.split(separator: ".", omittingEmptySubsequences: false)
            guard !suffix.isEmpty,
                  identifiers.allSatisfy({ !$0.isEmpty }) else {
                return nil
            }
            prerelease = identifiers.map(String.init)
        } else {
            core = value
            prerelease = []
        }

        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        var parsedComponents: [Int] = []
        for part in parts {
            guard let component = Int(part) else { return nil }
            parsedComponents.append(component)
        }
        components = parsedComponents
    }

    var displayString: String {
        var value = components.map(String.init).joined(separator: ".")
        if !prerelease.isEmpty {
            value += "-" + prerelease.joined(separator: ".")
        }
        return value
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            guard left == right else { return false }
        }
        return lhs.prerelease == rhs.prerelease
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }

        if lhs.prerelease == rhs.prerelease { return false }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        for index in 0..<min(lhs.prerelease.count, rhs.prerelease.count) {
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }

            let leftNumber = Int(left)
            let rightNumber = Int(right)
            switch (leftNumber, rightNumber) {
            case let (.some(leftNumber), .some(rightNumber)):
                return leftNumber < rightNumber
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

nonisolated struct UpdateAsset: Equatable, Sendable {
    let name: String
    let url: URL
    let size: Int64?
}

nonisolated struct UpdateRelease: Equatable, Sendable {
    let tagName: String
    let version: AppVersion
    let title: String
    let releaseNotes: String
    let publishedAt: Date?
    let pageURL: URL
    let downloadAsset: UpdateAsset?
    let checksumAsset: UpdateAsset?
}

nonisolated enum UpdateChecksumOutcome: Equatable, Sendable {
    case verified
    case unavailable
}

nonisolated struct UpdateFailure: Error, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case invalidCurrentVersion
        case invalidResponse
        case unstableRelease
        case network
        case checksumInvalid
        case checksumMismatch
        case download
        case fileMove
        case quarantine
        case open
    }

    let kind: Kind
    let detail: String?

    init(_ kind: Kind, detail: String? = nil) {
        self.kind = kind
        self.detail = detail
    }
}

nonisolated enum UpdatePhase: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(UpdateRelease)
    case downloading(UpdateRelease, progress: Double)
    case downloaded(
        UpdateRelease,
        fileURL: URL,
        checksum: UpdateChecksumOutcome,
        opened: Bool,
        quarantined: Bool
    )
    case failed(UpdateFailure)
    case downloadFailed(UpdateRelease, UpdateFailure)
}

nonisolated struct GitHubRelease: Decodable, Equatable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let publishedAt: String?
    let htmlURL: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: String
        let size: Int64?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

nonisolated protocol UpdateTransport: Sendable {
    func fetchLatestRelease() async throws -> GitHubRelease?
    func fetchData(from url: URL) async throws -> Data
    func download(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL
}

nonisolated enum UpdateReleaseMapper {
    static let repositoryURL = URL(string: "https://github.com/breeze-ev/hosts-manager")!
    static let latestReleaseAPIURL = URL(
        string: "https://api.github.com/repos/breeze-ev/hosts-manager/releases/latest"
    )!
    static let releasesPageURL = repositoryURL.appendingPathComponent("releases")

    static func map(_ release: GitHubRelease, architecture: String) throws -> UpdateRelease {
        guard !release.draft, !release.prerelease else {
            throw UpdateFailure(.unstableRelease)
        }
        guard let version = AppVersion(release.tagName) else {
            throw UpdateFailure(.invalidResponse, detail: release.tagName)
        }
        guard version.prerelease.isEmpty else {
            throw UpdateFailure(.unstableRelease)
        }

        let pageURL = httpsURL(release.htmlURL) ?? releaseTagURL(release.tagName)
        let matchingAssets = release.assets
            .enumerated()
            .compactMap { index, asset -> (index: Int, asset: UpdateAsset)? in
                guard asset.name.lowercased().hasSuffix(".dmg"),
                      asset.name.lowercased().contains(architecture.lowercased()),
                      let url = httpsURL(asset.browserDownloadURL) else {
                    return nil
                }
                return (index, UpdateAsset(name: asset.name, url: url, size: asset.size))
            }
            .sorted {
                let left = ($0.asset.name.lowercased(), $0.asset.url.absoluteString)
                let right = ($1.asset.name.lowercased(), $1.asset.url.absoluteString)
                if left != right {
                    return left < right
                }
                return $0.index < $1.index
            }
            .map(\.asset)
        let downloadAsset = matchingAssets.first
        let checksumName = downloadAsset.map { $0.name + ".sha256" }
        let checksumAsset: UpdateAsset? = release.assets.first(where: { asset in
            guard let checksumName else { return false }
            return asset.name.caseInsensitiveCompare(checksumName) == .orderedSame
                && httpsURL(asset.browserDownloadURL) != nil
        }).flatMap { asset -> UpdateAsset? in
            guard let url = httpsURL(asset.browserDownloadURL) else { return nil }
            return UpdateAsset(name: asset.name, url: url, size: asset.size)
        }

        return UpdateRelease(
            tagName: release.tagName,
            version: version,
            title: release.name?.isEmpty == false
                ? release.name!
                : "Hosts Manager \(version.displayString)",
            releaseNotes: release.body ?? "",
            publishedAt: parseDate(release.publishedAt),
            pageURL: pageURL,
            downloadAsset: downloadAsset,
            checksumAsset: checksumAsset
        )
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func httpsURL(_ value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }

    private static func releaseTagURL(_ tag: String) -> URL {
        var components = URLComponents(
            url: releasesPageURL.appendingPathComponent("tag"),
            resolvingAgainstBaseURL: false
        )!
        components.path = releasesPageURL.path + "/tag/" + tag
        return components.url ?? releasesPageURL
    }
}

nonisolated enum SHA256Verifier {
    static func digest(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func parse(_ text: String, expectedFileName: String) throws -> String {
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let digestField = fields.first else { continue }
            let digest = String(digestField).lowercased()
            guard digest.count == 64,
                  digest.allSatisfy(\.isHexDigit) else {
                continue
            }
            guard fields.count >= 2 else { continue }
            var fileName = String(fields[1])
            if fileName.hasPrefix("*") {
                fileName.removeFirst()
            }
            if URL(fileURLWithPath: fileName).lastPathComponent
                .caseInsensitiveCompare(expectedFileName) == .orderedSame {
                return digest
            }
        }
        throw UpdateFailure(.checksumInvalid)
    }
}

nonisolated enum UpdateQuarantine {
    static func apply(
        to fileURL: URL,
        downloadURL: URL,
        originURL: URL
    ) throws {
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineDataURLKey as String: downloadURL,
            kLSQuarantineOriginURLKey as String: originURL
        ]
        var mutableURL = fileURL
        try mutableURL.setResourceValues(values)
    }
}

nonisolated enum UpdateFileNaming {
    static func uniqueDestination(
        directory: URL,
        fileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        let candidateName = safeName.isEmpty ? "Hosts-Manager.dmg" : safeName
        let original = directory.appendingPathComponent(candidateName)
        guard fileManager.fileExists(atPath: original.path) else {
            return original
        }

        let source = URL(fileURLWithPath: candidateName)
        let stem = source.deletingPathExtension().lastPathComponent
        let pathExtension = source.pathExtension
        var index = 2
        while true {
            let numberedName = pathExtension.isEmpty
                ? "\(stem) (\(index))"
                : "\(stem) (\(index)).\(pathExtension)"
            let candidate = directory.appendingPathComponent(numberedName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}

extension Notification.Name {
    static let closeUpdateWindow = Notification.Name("UpdateCenterCloseWindow")
}

nonisolated final class URLSessionUpdateTransport: UpdateTransport {
    nonisolated private let apiSession: URLSession
    nonisolated private let downloadSession: URLSession

    init() {
        let apiConfiguration = URLSessionConfiguration.ephemeral
        apiConfiguration.timeoutIntervalForRequest = 15
        apiConfiguration.timeoutIntervalForResource = 15
        apiConfiguration.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "User-Agent": "Hosts-Manager-Update-Check"
        ]
        apiSession = URLSession(configuration: apiConfiguration)

        let downloadConfiguration = URLSessionConfiguration.ephemeral
        downloadConfiguration.timeoutIntervalForRequest = 300
        downloadConfiguration.timeoutIntervalForResource = 300
        downloadConfiguration.httpAdditionalHeaders = [
            "User-Agent": "Hosts-Manager-Update-Check"
        ]
        downloadSession = URLSession(configuration: downloadConfiguration)
    }

    func fetchLatestRelease() async throws -> GitHubRelease? {
        var request = URLRequest(url: UpdateReleaseMapper.latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Hosts-Manager-Update-Check", forHTTPHeaderField: "User-Agent")
        let (firstData, firstResponse) = try await Self.releaseResponse(
            from: request,
            session: downloadSession
        )
        if firstResponse.statusCode == 403,
           let retryAfter = Self.retryAfterInterval(from: firstResponse) {
            try? await Task.sleep(for: .seconds(retryAfter))
            return try await Self.releasePayload(from: request, session: downloadSession)
        }
        return try Self.releasePayload(from: firstData, response: firstResponse)
    }

    func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Hosts-Manager-Update-Check", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await apiSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateFailure(.network, detail: "Unable to fetch checksum")
        }
        return data
    }

    nonisolated private static func releaseResponse(
        from request: URLRequest,
        session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateFailure(.network, detail: "Invalid HTTP response")
        }
        return (data, httpResponse)
    }

    nonisolated private static func releasePayload(
        from request: URLRequest,
        session: URLSession
    ) async throws -> GitHubRelease? {
        let (data, httpResponse) = try await releaseResponse(from: request, session: session)
        return try releasePayload(from: data, response: httpResponse)
    }

    nonisolated private static func releasePayload(
        from data: Data,
        response httpResponse: HTTPURLResponse
    ) throws -> GitHubRelease? {
        if httpResponse.statusCode == 404 {
            return nil
        }
        guard httpResponse.statusCode == 200 else {
            throw UpdateFailure(.network, detail: "HTTP \(httpResponse.statusCode)")
        }
        do {
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateFailure(.invalidResponse, detail: error.localizedDescription)
        }
    }

    nonisolated private static func retryAfterInterval(
        from response: HTTPURLResponse
    ) -> TimeInterval? {
        guard let retryAfterHeader = response.value(forHTTPHeaderField: "Retry-After"),
              let retryAfter = TimeInterval(retryAfterHeader),
              retryAfter > 0 else {
            return nil
        }
        return min(retryAfter, 2)
    }

    func download(
        from url: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        request.setValue("Hosts-Manager-Update-Check", forHTTPHeaderField: "User-Agent")
        let delegate = UpdateDownloadDelegate(progress: progress)
        let (temporaryURL, response) = try await downloadSession.download(
            for: request,
            delegate: delegate
        )
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateFailure(.download, detail: "Unable to download update")
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hosts-Manager-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.copyItem(at: temporaryURL, to: destination)
            try? FileManager.default.removeItem(at: temporaryURL)
            return destination
        } catch {
            throw UpdateFailure(.download, detail: error.localizedDescription)
        }
    }
}

private final class UpdateDownloadDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    private let progress: (Double) -> Void

    init(progress: @escaping (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}

@MainActor
final class UpdateCenter: ObservableObject {
    @Published private(set) var phase: UpdatePhase = .idle
    @Published var isPanelPresented = false
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var lastCheckSucceeded: Bool?
    private(set) var isPresentationBlocked = false

    let currentVersionString: String?
    let currentBuildNumber: String
    let automaticChecksEnabled: Bool
    private var hasPresentedCurrentRelease = false

    private static let lastCheckDateKey = "updates.lastCheckDate"
    private static let lastCheckSucceededKey = "updates.lastCheckSucceeded"
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    private let transport: UpdateTransport
    private let defaults: UserDefaults
    private let now: () -> Date
    private let downloadsDirectory: URL
    private let quarantineWriter: (URL, URL, URL) throws -> Void
    private let opener: @MainActor (URL) -> Bool
    private let activator: @MainActor () -> Void
    private let revealer: @MainActor (URL) -> Void

    private var checkTask: Task<Bool, Never>?
    private var downloadTask: Task<Bool, Never>?
    private var activeCheckID: UUID?
    private var activeDownloadID: UUID?
    private var downloadedTemporaryURL: URL?
    private var pendingPresentation = false
    private var pendingPresentationShouldActivate = false
    private var isManualCheckRequested = false

    init(
        currentVersionString: String? = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String,
        currentBuildNumber: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—",
        transport: UpdateTransport = URLSessionUpdateTransport(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        downloadsDirectory: URL? = nil,
        automaticChecksEnabled: Bool = true,
        quarantineWriter: @escaping (URL, URL, URL) throws -> Void = {
            try UpdateQuarantine.apply(to: $0, downloadURL: $1, originURL: $2)
        },
        opener: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        activator: @escaping @MainActor () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
        },
        revealer: @escaping @MainActor (URL) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting([$0])
        }
    ) {
        self.currentVersionString = currentVersionString
        self.currentBuildNumber = currentBuildNumber
        self.transport = transport
        self.defaults = defaults
        self.now = now
        self.downloadsDirectory = downloadsDirectory ?? Self.defaultDownloadsDirectory
        self.automaticChecksEnabled = automaticChecksEnabled
        self.quarantineWriter = quarantineWriter
        self.opener = opener
        self.activator = activator
        self.revealer = revealer
        self.lastCheckDate = defaults.object(forKey: Self.lastCheckDateKey) as? Date
        if defaults.object(forKey: Self.lastCheckSucceededKey) != nil {
            self.lastCheckSucceeded = defaults.bool(forKey: Self.lastCheckSucceededKey)
        }
    }

    var displayedVersion: String {
        currentVersionString ?? "—"
    }

    var isChecking: Bool {
        if case .checking = phase { return true }
        return checkTask != nil
    }

    var isDownloading: Bool {
        if case .downloading = phase { return true }
        return downloadTask != nil
    }

    var currentRelease: UpdateRelease? {
        switch phase {
        case .available(let release),
             .downloadFailed(let release, _):
            return release
        case .downloading(let release, _),
             .downloaded(let release, _, _, _, _):
            return release
        case .idle, .checking, .upToDate, .failed:
            return nil
        }
    }

    func checkAutomaticallyIfDue() async {
        guard automaticChecksEnabled else { return }
        if let lastCheckDate,
           now().timeIntervalSince(lastCheckDate) < Self.automaticCheckInterval {
            return
        }
        _ = await checkForUpdates(manual: false)
    }

    @discardableResult
    func checkForUpdates(manual: Bool) async -> Bool {
        if let checkTask {
            if manual {
                isManualCheckRequested = true
                requestPanelPresentation()
            }
            return await checkTask.value
        }
        if currentRelease != nil {
            if manual {
                requestPanelPresentation()
            }
            return true
        }
        if manual {
            requestPanelPresentation()
        }

        let checkID = UUID()
        activeCheckID = checkID
        isManualCheckRequested = manual
        let task = Task { await performCheck(manual: manual) }
        checkTask = task
        let succeeded = await task.value
        if activeCheckID == checkID {
            checkTask = nil
            activeCheckID = nil
        }
        return succeeded
    }

    @discardableResult
    func downloadAndOpen() async -> Bool {
        if let downloadTask {
            if !hasPresentedCurrentRelease {
                requestPanelPresentation()
            }
            return await downloadTask.value
        }
        guard let release = currentRelease,
              let asset = release.downloadAsset else {
            requestPanelPresentation()
            return false
        }
        switch phase {
        case .downloaded, .downloading:
            if !hasPresentedCurrentRelease {
                requestPanelPresentation()
            }
            return true
        default:
            break
        }

        if !hasPresentedCurrentRelease {
            requestPanelPresentation()
        }
        let downloadID = UUID()
        activeDownloadID = downloadID
        let task = Task {
            await performDownload(release, asset: asset, downloadID: downloadID)
        }
        downloadTask = task
        let succeeded = await task.value
        if activeDownloadID == downloadID {
            downloadTask = nil
            activeDownloadID = nil
        }
        return succeeded
    }

    func cancelDownload() {
        guard case .downloading(let release, _) = phase else { return }
        pendingPresentation = false
        downloadTask?.cancel()
        if let downloadedTemporaryURL {
            try? FileManager.default.removeItem(at: downloadedTemporaryURL)
            self.downloadedTemporaryURL = nil
        }
        phase = .available(release)
    }

    func presentPanel() {
        guard !isPresentationBlocked else { return }
        isPanelPresented = true
        if currentRelease != nil {
            hasPresentedCurrentRelease = true
        }
    }

    private func requestPanelPresentation(activate: Bool = false) {
        if isPresentationBlocked {
            pendingPresentation = true
            pendingPresentationShouldActivate = pendingPresentationShouldActivate || activate
        } else {
            presentPanel()
            if activate {
                activator()
            }
        }
    }

    func dismissPanel() {
        isPanelPresented = false
    }

    func panelDidDismiss() {
        hasPresentedCurrentRelease = false
        isPanelPresented = false
        pendingPresentation = false
        pendingPresentationShouldActivate = false
    }

    func publishPanelDismissal() {
        panelDidDismiss()
        NotificationCenter.default.post(name: .closeUpdateWindow, object: nil)
    }

    func setPresentationBlocked(_ blocked: Bool, autoPresentOnUnblock: Bool = true) {
        guard isPresentationBlocked != blocked else { return }
        isPresentationBlocked = blocked
        guard !blocked, autoPresentOnUnblock,
              pendingPresentation else {
            return
        }
        pendingPresentation = false
        presentPanel()
        hasPresentedCurrentRelease = true
        if pendingPresentationShouldActivate {
            pendingPresentationShouldActivate = false
            activator()
        }
    }

    func openReleasePage() {
        let url = currentRelease?.pageURL ?? UpdateReleaseMapper.releasesPageURL
        _ = opener(url)
    }

    func revealDownloadedFile() {
        guard case .downloaded(_, let fileURL, _, _, _) = phase else { return }
        revealer(fileURL)
    }

    @discardableResult
    func retryOpeningDownloadedFile() -> Bool {
        guard case .downloaded(let release, let fileURL, let checksum, _, _) = phase,
              let asset = release.downloadAsset else {
            return false
        }

        var quarantined = true
        do {
            try quarantineWriter(fileURL, asset.url, release.pageURL)
        } catch {
            quarantined = false
        }
        let opened = quarantined && opener(fileURL)
        phase = .downloaded(
            release,
            fileURL: fileURL,
            checksum: checksum,
            opened: opened,
            quarantined: quarantined
        )
        return opened
    }

    private func performCheck(manual: Bool) async -> Bool {
        phase = .checking
        guard let currentVersion = currentVersionString.flatMap(AppVersion.init) else {
            return finishCheck(
                with: .failed(UpdateFailure(.invalidCurrentVersion)),
                succeeded: false,
                manual: manual
            )
        }

        do {
            guard let latestRelease = try await transport.fetchLatestRelease() else {
                return finishCheck(with: .upToDate, succeeded: true, manual: manual)
            }
            let release: UpdateRelease
            do {
                release = try UpdateReleaseMapper.map(
                    latestRelease,
                    architecture: Self.currentArchitecture
                )
            } catch let failure as UpdateFailure {
                return finishCheck(
                    with: .failed(failure),
                    succeeded: false,
                    manual: manual
                )
            }

            if release.version > currentVersion {
                phase = .available(release)
                let shouldPresent = manual || isManualCheckRequested
                isManualCheckRequested = false
                if isPresentationBlocked {
                    pendingPresentation = true
                    pendingPresentationShouldActivate = !shouldPresent
                } else {
                    presentPanel()
                    hasPresentedCurrentRelease = true
                    pendingPresentation = false
                    if !shouldPresent {
                        activator()
                    }
                }
                persistCheckResult(succeeded: true)
                return shouldPresent || !isPresentationBlocked
            }
            return finishCheck(with: .upToDate, succeeded: true, manual: manual)
        } catch let failure as UpdateFailure {
            return finishCheck(with: .failed(failure), succeeded: false, manual: manual)
        } catch {
            return finishCheck(
                with: .failed(.init(.network, detail: error.localizedDescription)),
                succeeded: false,
                manual: manual
            )
        }
    }

    private func finishCheck(
        with nextPhase: UpdatePhase,
        succeeded: Bool,
        manual: Bool
    ) -> Bool {
        let shouldPresent = manual || isManualCheckRequested
        isManualCheckRequested = false
        phase = shouldPresent || succeeded ? nextPhase : .idle
        persistCheckResult(succeeded: succeeded)
        if shouldPresent {
            if isPresentationBlocked {
                pendingPresentation = true
            } else {
                presentPanel()
                pendingPresentation = false
            }
        }
        return succeeded
    }

    private func persistCheckResult(succeeded: Bool) {
        let date = now()
        lastCheckDate = date
        lastCheckSucceeded = succeeded
        defaults.set(date, forKey: Self.lastCheckDateKey)
        defaults.set(succeeded, forKey: Self.lastCheckSucceededKey)
    }

    private func performDownload(
        _ release: UpdateRelease,
        asset: UpdateAsset,
        downloadID: UUID
    ) async -> Bool {
        phase = .downloading(release, progress: 0)

        do {
            let downloadedURL = try await transport.download(from: asset.url) { [weak self] fraction in
                Task { @MainActor in
                    guard let self,
                          self.activeDownloadID == downloadID,
                          case .downloading(let currentRelease, _) = self.phase else {
                        return
                    }
                    self.phase = .downloading(
                        currentRelease,
                        progress: min(max(fraction, 0), 1)
                    )
                }
            }
            downloadedTemporaryURL = downloadedURL
            try Task.checkCancellation()

            let checksum = try await verifyChecksum(
                for: asset,
                checksumAsset: release.checksumAsset,
                downloadedURL: downloadedURL
            )
            try Task.checkCancellation()

            let destination: URL
            do {
                destination = try UpdateFileNaming.uniqueDestination(
                    directory: downloadsDirectory,
                    fileName: asset.name
                )
            } catch {
                throw UpdateFailure(.fileMove, detail: error.localizedDescription)
            }
            do {
                try FileManager.default.moveItem(at: downloadedURL, to: destination)
            } catch {
                throw UpdateFailure(.fileMove, detail: error.localizedDescription)
            }
            downloadedTemporaryURL = nil

            var quarantined = true
            do {
                try quarantineWriter(destination, asset.url, release.pageURL)
            } catch {
                quarantined = false
            }
            let opened = quarantined && opener(destination)
            phase = .downloaded(
                release,
                fileURL: destination,
                checksum: checksum,
                opened: opened,
                quarantined: quarantined
            )
            if isPresentationBlocked {
                pendingPresentation = true
            } else {
                if !hasPresentedCurrentRelease {
                    presentPanel()
                    hasPresentedCurrentRelease = true
                }
                pendingPresentation = false
            }
            return true
        } catch is CancellationError {
            cleanupDownloadedTemporaryFile()
            phase = .available(release)
            return false
        } catch let error as URLError where error.code == .cancelled {
            cleanupDownloadedTemporaryFile()
            phase = .available(release)
            return false
        } catch let failure as UpdateFailure {
            cleanupDownloadedTemporaryFile()
            phase = .downloadFailed(release, failure)
            return false
        } catch {
            cleanupDownloadedTemporaryFile()
            phase = .downloadFailed(
                release,
                .init(.download, detail: error.localizedDescription)
            )
            return false
        }
    }

    private func cleanupDownloadedTemporaryFile() {
        if let downloadedTemporaryURL {
            try? FileManager.default.removeItem(at: downloadedTemporaryURL)
        }
        downloadedTemporaryURL = nil
    }

    private func verifyChecksum(
        for asset: UpdateAsset,
        checksumAsset: UpdateAsset?,
        downloadedURL: URL
    ) async throws -> UpdateChecksumOutcome {
        guard let checksumAsset else {
            return .unavailable
        }
        let data: Data
        do {
            data = try await transport.fetchData(from: checksumAsset.url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return .unavailable
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw UpdateFailure(.checksumInvalid)
        }
        let expected = try SHA256Verifier.parse(text, expectedFileName: asset.name)
        let actual = try SHA256Verifier.digest(of: downloadedURL)
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw UpdateFailure(
                .checksumMismatch,
                detail: "\(actual) != \(expected)"
            )
        }
        return .verified
    }

    private static var defaultDownloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
    }

    nonisolated static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

}

extension UpdateCenter {
    static func forCurrentProcess() -> UpdateCenter {
        let arguments = ProcessInfo.processInfo.arguments
        guard let modeIndex = arguments.firstIndex(of: "-UITestUpdateMode"),
              arguments.indices.contains(modeIndex + 1) else {
            return UpdateCenter()
        }
        let mode = arguments[modeIndex + 1]
        return makeUITest(mode: mode)
    }

    private static func makeUITest(mode: String) -> UpdateCenter {
        let transport = UITestUpdateTransport(mode: mode)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hosts-manager-ui-updates-\(UUID().uuidString)", isDirectory: true)
        return UpdateCenter(
            currentVersionString: "0.1.0",
            currentBuildNumber: "6",
            transport: transport,
            defaults: UserDefaults(suiteName: "hosts-manager-ui-tests-\(UUID().uuidString)")!,
            downloadsDirectory: directory,
            automaticChecksEnabled: false,
            quarantineWriter: { _, _, _ in },
            opener: { _ in true },
            activator: {},
            revealer: { _ in }
        )
    }
}

private final class UITestUpdateTransport: UpdateTransport {
    let mode: String

    init(mode: String) {
        self.mode = mode
    }

    func fetchLatestRelease() async throws -> GitHubRelease? {
        if mode == "failure" {
            throw UpdateFailure(.network, detail: "UI test network failure")
        }
        let version = mode == "upToDate" ? "v0.1.0" : "v9.9.9"
        return GitHubRelease(
            tagName: version,
            name: "Hosts Manager \(version)",
            body: "UI test release notes.",
            publishedAt: "2026-10-27T00:00:00Z",
            htmlURL: "https://github.com/breeze-ev/hosts-manager/releases/tag/\(version)",
            draft: false,
            prerelease: false,
            assets: [
                .init(
                    name: "Hosts-Manager-9.9.9-1-arm64.dmg",
                    browserDownloadURL: "https://example.com/Hosts-Manager-9.9.9-1-arm64.dmg",
                    size: 8
                ),
                .init(
                    name: "Hosts-Manager-9.9.9-1-x86_64.dmg",
                    browserDownloadURL: "https://example.com/Hosts-Manager-9.9.9-1-x86_64.dmg",
                    size: 8
                )
            ]
        )
    }

    func fetchData(from url: URL) async throws -> Data {
        throw URLError(.fileDoesNotExist)
    }

    func download(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        if mode == "downloadFailure" {
            throw URLError(.networkConnectionLost)
        }
        progress(1)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hosts-Manager-UI-\(UUID().uuidString).dmg")
        try Data("fake dmg".utf8).write(to: fileURL)
        return fileURL
    }
}

struct UpdateSheet: View {
    @ObservedObject var updateCenter: UpdateCenter
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear,
                    Color.primary.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
                Divider()
                footer
                    .padding(18)
            }
        }
        .frame(width: 620, height: 540)
        .onDisappear {
            if updateCenter.isPanelPresented {
                updateCenter.panelDidDismiss()
            }
        }
        .accessibilityIdentifier("update-panel")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.accentColor.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.s("软件更新", "Software Update"))
                    .font(.system(size: 21, weight: .bold))
                Text(l10n.s(
                    "当前版本 \(updateCenter.displayedVersion)（\(updateCenter.currentBuildNumber)）",
                    "Current version \(updateCenter.displayedVersion) (\(updateCenter.currentBuildNumber))"
                ))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                updateCenter.publishPanelDismissal()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help(l10n.s("稍后", "Later"))
            .accessibilityIdentifier("update-close-button")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch updateCenter.phase {
        case .idle, .checking:
            checkingContent
        case .upToDate:
            upToDateContent
        case .available(let release):
            releaseContent(release, failure: nil)
        case .downloading(let release, let progress):
            downloadingContent(release, progress: progress)
        case .downloaded(
            let release,
            let fileURL,
            let checksum,
            let opened,
            let quarantined
        ):
            downloadedContent(
                release,
                fileURL: fileURL,
                checksum: checksum,
                opened: opened,
                quarantined: quarantined
            )
        case .failed(let failure):
            failureContent(failure)
        case .downloadFailed(let release, let failure):
            releaseContent(release, failure: failure)
        }
    }

    private var checkingContent: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(l10n.s("正在检查更新…", "Checking for updates…"))
                .accessibilityIdentifier("update-checking")
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var upToDateContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.s("已是最新版本", "You’re up to date"), systemImage: "checkmark.seal.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.green)
                .accessibilityIdentifier("update-up-to-date")
            Text(l10n.s(
                "Hosts Manager 当前版本为 \(updateCenter.displayedVersion)。",
                "Hosts Manager \(updateCenter.displayedVersion) is the latest available version."
            ))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    private func releaseContent(
        _ release: UpdateRelease,
        failure: UpdateFailure?
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.s("发现新版本", "Update Available"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .textCase(.uppercase)
                Text(release.title)
                    .font(.system(size: 24, weight: .bold))
                    .accessibilityIdentifier("update-version-title")
                HStack(spacing: 12) {
                    Text(release.version.displayString)
                    if let publishedAt = release.publishedAt {
                        Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            }

            if release.downloadAsset == nil {
                Label(
                    l10n.s(
                        "此版本没有适配当前 Mac 芯片的 DMG。",
                        "This release has no DMG for this Mac’s architecture."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }

            if let failure {
                failureBanner(failure)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.s("发布说明", "Release Notes"))
                    .font(.system(size: 13, weight: .semibold))
                Text(release.releaseNotes.isEmpty
                    ? l10n.s("此版本没有提供发布说明。", "No release notes were provided.")
                    : release.releaseNotes)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.12)))
        }
    }

    private func downloadingContent(_ release: UpdateRelease, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(release.title)
                .font(.system(size: 22, weight: .bold))
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .accessibilityIdentifier("update-download-progress")
            HStack {
                Text(l10n.s("正在下载更新…", "Downloading update…"))
                Spacer()
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            Text(l10n.s(
                "下载完成后会在 Downloads 中保存并自动打开 DMG。",
                "When complete, the DMG will be saved in Downloads and opened automatically."
            ))
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
    }

    private func downloadedContent(
        _ release: UpdateRelease,
        fileURL: URL,
        checksum: UpdateChecksumOutcome,
        opened: Bool,
        quarantined: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                opened
                    ? l10n.s("更新已下载并打开", "Update Downloaded and Opened")
                    : l10n.s("更新已下载", "Update Downloaded"),
                systemImage: "checkmark.circle.fill"
            )
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(.green)
            .accessibilityIdentifier("update-downloaded")

            Text(release.title)
                .font(.system(size: 15, weight: .medium))
            Text(fileURL.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 7) {
                Label(
                    checksum == .verified
                        ? l10n.s("SHA-256 校验通过", "SHA-256 verified")
                        : l10n.s(
                            "未找到校验文件，安装包交由 Gatekeeper 检查",
                            "Checksum unavailable; Gatekeeper will inspect the package"
                        ),
                    systemImage: checksum == .verified ? "checkmark.shield.fill" : "shield"
                )
                if !quarantined {
                    Label(
                        l10n.s(
                            "无法写入下载隔离信息，因此没有自动打开。",
                            "Download quarantine metadata could not be written, so the DMG was not opened automatically."
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                } else if !opened {
                    Label(
                        l10n.s(
                            "无法自动打开 DMG，请从 Finder 手动打开。",
                            "The DMG could not be opened automatically. Open it from Finder."
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)

            Text(l10n.s(
                "将 Hosts Manager 拖入 Applications 以完成安装。",
                "Drag Hosts Manager into Applications to finish installing."
            ))
            .font(.system(size: 13))
        }
        .padding(.vertical, 8)
    }

    private func failureContent(_ failure: UpdateFailure) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(l10n.s("无法检查更新", "Unable to Check for Updates"), systemImage: "wifi.exclamationmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.orange)
            failureBanner(failure)
            Text(l10n.s(
                "请检查网络连接后重试，或从 GitHub Releases 手动下载。",
                "Check your network connection and try again, or download manually from GitHub Releases."
            ))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    private func failureBanner(_ failure: UpdateFailure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(failureMessage(failure))
                .font(.system(size: 13, weight: .medium))
            if let detail = failure.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            if case .downloaded = updateCenter.phase {
                Button(l10n.s("在 Finder 中显示", "Show in Finder")) {
                    updateCenter.revealDownloadedFile()
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("update-show-in-finder")
                if case .downloaded(_, _, _, let opened, let quarantined) = updateCenter.phase,
                   !opened || !quarantined {
                    Button(l10n.s("重试打开", "Retry Open")) {
                        updateCenter.retryOpeningDownloadedFile()
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("update-retry-open")
                }
            }

            if updateCenter.currentRelease != nil {
                Button(l10n.s("打开发布页", "Open Release Page")) {
                    updateCenter.openReleasePage()
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("update-open-release-page")
            }

            Spacer()

            switch updateCenter.phase {
            case .available:
                Button(l10n.s("稍后", "Later")) {
                    updateCenter.publishPanelDismissal()
                }
                .buttonStyle(.glass)
                Button(l10n.s("下载并打开", "Download and Open")) {
                    Task { await updateCenter.downloadAndOpen() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(updateCenter.currentRelease?.downloadAsset == nil)
                .accessibilityIdentifier("update-download-button")
            case .downloading:
                Button(l10n.s("取消下载", "Cancel Download"), role: .destructive) {
                    updateCenter.cancelDownload()
                }
                .buttonStyle(.glass)
            case .downloadFailed:
                Button(l10n.s("重试下载", "Retry Download")) {
                    Task { await updateCenter.downloadAndOpen() }
                }
                .buttonStyle(.borderedProminent)
            case .failed:
                Button(l10n.s("打开发布页", "Open Release Page")) {
                    updateCenter.openReleasePage()
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("update-open-release-page")
                Button(l10n.s("重试", "Retry")) {
                    Task { await updateCenter.checkForUpdates(manual: true) }
                }
                .buttonStyle(.borderedProminent)
            default:
                Button(l10n.s("完成", "Done")) {
                    updateCenter.publishPanelDismissal()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func failureMessage(_ failure: UpdateFailure) -> String {
        switch failure.kind {
        case .invalidCurrentVersion:
            return l10n.s("无法读取当前应用版本。", "The current app version could not be read.")
        case .invalidResponse:
            return l10n.s("GitHub 返回了无法识别的发布信息。", "GitHub returned an invalid release response.")
        case .unstableRelease:
            return l10n.s("当前只接收正式版本。", "Only stable releases are accepted.")
        case .network:
            return l10n.s("网络请求失败。", "The network request failed.")
        case .checksumInvalid:
            return l10n.s("更新包的校验文件无效。", "The update checksum file is invalid.")
        case .checksumMismatch:
            return l10n.s("SHA-256 校验不匹配，已阻止打开。", "The SHA-256 checksum did not match, so the file was not opened.")
        case .download:
            return l10n.s("下载更新失败。", "The update could not be downloaded.")
        case .fileMove:
            return l10n.s("无法将更新保存到 Downloads。", "The update could not be saved to Downloads.")
        case .quarantine:
            return l10n.s("无法标记下载文件。", "The downloaded file could not be quarantined.")
        case .open:
            return l10n.s("无法打开更新包。", "The update package could not be opened.")
        }
    }
}
