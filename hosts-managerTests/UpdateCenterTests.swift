import Foundation
import Testing
@testable import hosts_manager

struct UpdateVersionTests {
    @Test func parsesLooseNumericVersions() throws {
        let version = try #require(AppVersion("  V1.2+build.9 "))
        #expect(version.components == [1, 2])
        #expect(version.prerelease.isEmpty)
        #expect(version.displayString == "1.2")

        let prerelease = try #require(AppVersion("v0.1.0-beta.2+exp.sha.5114f85"))
        #expect(prerelease.components == [0, 1, 0])
        #expect(prerelease.prerelease == ["beta", "2"])
        #expect(prerelease.displayString == "0.1.0-beta.2")
    }

    @Test func comparesNumericSegmentsAndIgnoresBuildMetadata() throws {
        let one = try #require(AppVersion("1"))
        let onePointZero = try #require(AppVersion("1.0.0+42"))
        let next = try #require(AppVersion("1.0.1"))

        #expect(one == onePointZero)
        #expect(!(one < onePointZero))
        #expect(one < next)
        let two = try #require(AppVersion("2.0"))
        let onePointNinetyNine = try #require(AppVersion("1.99.99"))
        #expect(two > onePointNinetyNine)
    }

    @Test func ordersPrereleasesBeforeStableReleases() throws {
        let alpha = try #require(AppVersion("1.0.0-alpha"))
        let alphaOne = try #require(AppVersion("1.0.0-alpha.1"))
        let alphaTwo = try #require(AppVersion("1.0.0-alpha.2"))
        let beta = try #require(AppVersion("1.0.0-beta"))
        let numeric = try #require(AppVersion("1.0.0-2"))
        let stable = try #require(AppVersion("1.0.0"))

        #expect(alpha < alphaOne)
        #expect(alphaOne < alphaTwo)
        #expect(alphaTwo < beta)
        #expect(beta < stable)
        #expect(numeric < alpha)
        let ten = try #require(AppVersion("1.0.0-10"))
        #expect(numeric < ten)
    }

    @Test func rejectsMalformedVersions() {
        for rawValue in ["", "v", "1..0", "1.a", "-1.0", "1.0-", "1.0.0-rc..1"] {
            #expect(AppVersion(rawValue) == nil, "Expected \(rawValue) to be rejected")
        }
    }
}

struct UpdateReleaseMapperTests {
    @Test func choosesArchitectureCaseInsensitively() throws {
        let release = makeGitHubRelease(assets: [
            asset("Hosts-Manager-1.2.0-ARM64.DMG")
        ])

        let mapped = try UpdateReleaseMapper.map(
            release,
            architecture: UpdateCenter.currentArchitecture
        )

        #expect(mapped.downloadAsset?.name == "Hosts-Manager-1.2.0-ARM64.DMG")
    }

    @Test func mapsStableReleaseAndArchitectureAssets() throws {
        let release = makeGitHubRelease(
            tag: "v1.2.0",
            name: "Hosts Manager 1.2.0",
            assets: [
                asset("Hosts-Manager-1.2.0-x86_64.dmg"),
                asset("Hosts-Manager-1.2.0-arm64.dmg"),
                asset("Hosts-Manager-1.2.0-arm64.zip"),
                asset(
                    "Hosts-Manager-1.2.0-arm64-unsigned.dmg",
                    url: "http://example.com/insecure.dmg"
                )
            ]
        )

        let mapped = try UpdateReleaseMapper.map(release, architecture: "arm64")

        #expect(mapped.version == (try #require(AppVersion("1.2.0"))))
        #expect(mapped.title == "Hosts Manager 1.2.0")
        #expect(mapped.releaseNotes == "Release notes")
        #expect(mapped.downloadAsset?.name == "Hosts-Manager-1.2.0-arm64.dmg")
        #expect(mapped.checksumAsset == nil)
        #expect(mapped.pageURL.scheme == "https")
    }

    @Test func choosesRequestedArchitecture() throws {
        let release = makeGitHubRelease(assets: [
            asset("Hosts-Manager-1.2.0-arm64.dmg"),
            asset("Hosts-Manager-1.2.0-x86_64.dmg")
        ])

        let mapped = try UpdateReleaseMapper.map(release, architecture: "x86_64")
        #expect(mapped.downloadAsset?.name == "Hosts-Manager-1.2.0-x86_64.dmg")
    }

    @Test func sortsCandidateNamesStablyAndChoosesChecksum() throws {
        let selectedName = "A-arm64.dmg"
        let release = makeGitHubRelease(assets: [
            asset("z-arm64.dmg", url: "https://example.com/z.dmg"),
            asset("Hosts-Manager-1.2.0-arm64.dmg", url: "https://example.com/h.dmg"),
            asset(selectedName, url: "https://example.com/a.dmg"),
            asset(
                "\(selectedName).sha256",
                url: "https://example.com/a.dmg.sha256"
            )
        ])

        let mapped = try UpdateReleaseMapper.map(release, architecture: "arm64")
        #expect(mapped.downloadAsset?.name == selectedName)
        #expect(mapped.checksumAsset?.name == "\(selectedName).sha256")
    }

    @Test func rejectsDraftAndPrereleaseResponses() {
        for release in [
            makeGitHubRelease(draft: true),
            makeGitHubRelease(prerelease: true),
            makeGitHubRelease(tag: "v2.0.0-beta.1")
        ] {
            do {
                _ = try UpdateReleaseMapper.map(release, architecture: "arm64")
                Issue.record("Expected unstable release to be rejected")
            } catch let failure as UpdateFailure {
                #expect(failure.kind == .unstableRelease)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test func rejectsInvalidTagAndFallsBackToHTTPSReleasePage() throws {
        let invalid = makeGitHubRelease(tag: "release-latest")
        do {
            _ = try UpdateReleaseMapper.map(invalid, architecture: "arm64")
            Issue.record("Expected invalid tag to be rejected")
        } catch let failure as UpdateFailure {
            #expect(failure.kind == .invalidResponse)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let valid = makeGitHubRelease(
            tag: "v2.0",
            htmlURL: "http://example.com/insecure-release"
        )
        let mapped = try UpdateReleaseMapper.map(valid, architecture: "arm64")
        #expect(mapped.pageURL.scheme == "https")
        #expect(mapped.pageURL.absoluteString.contains("/releases/tag/v2.0"))
    }

    @Test func decodesGitHubJSONAndParsesDates() throws {
        let json = """
        {
          "tag_name": "v1.4.0",
          "name": "Version 1.4",
          "body": "Notes",
          "published_at": "2026-10-27T12:34:56Z",
          "html_url": "https://github.com/breeze-ev/hosts-manager/releases/tag/v1.4.0",
          "draft": false,
          "prerelease": false,
          "assets": []
        }
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(release.tagName == "v1.4.0")
        #expect(UpdateReleaseMapper.parseDate(release.publishedAt) != nil)
    }
}

struct UpdateChecksumAndFileTests {
    @Test func parsesSHA256SumsWithAbsolutePathsAndBinaryMarkers() throws {
        let digest = String(repeating: "a", count: 64)
        let text = """
        \(String(repeating: "0", count: 64))  /tmp/other.dmg
        \(digest) */Users/test/Downloads/Hosts-Manager-1.2.0-arm64.dmg
        """

        let parsed = try SHA256Verifier.parse(
            text,
            expectedFileName: "Hosts-Manager-1.2.0-arm64.dmg"
        )
        #expect(parsed == digest)
    }

    @Test func rejectsMalformedChecksumText() {
        #expect(throws: UpdateFailure.self) {
            try SHA256Verifier.parse(
                "not-a-checksum  Hosts-Manager-1.2.0-arm64.dmg",
                expectedFileName: "Hosts-Manager-1.2.0-arm64.dmg"
            )
        }
        #expect(throws: UpdateFailure.self) {
            try SHA256Verifier.parse(
                "\(String(repeating: "a", count: 64))  another.dmg",
                expectedFileName: "Hosts-Manager-1.2.0-arm64.dmg"
            )
        }
    }

    @Test func uniqueDestinationNeverOverwrites() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try UpdateFileNaming.uniqueDestination(
            directory: directory,
            fileName: "Hosts-Manager.dmg"
        )
        #expect(first.lastPathComponent == "Hosts-Manager.dmg")
        try Data("first".utf8).write(to: first)

        let second = try UpdateFileNaming.uniqueDestination(
            directory: directory,
            fileName: "Hosts-Manager.dmg"
        )
        #expect(second.lastPathComponent == "Hosts-Manager (2).dmg")
        try Data("second".utf8).write(to: second)

        let third = try UpdateFileNaming.uniqueDestination(
            directory: directory,
            fileName: "Hosts-Manager.dmg"
        )
        #expect(third.lastPathComponent == "Hosts-Manager (3).dmg")
        #expect(try String(contentsOf: first, encoding: .utf8) == "first")
    }
}

@MainActor
struct UpdateCenterStateTests {
    @Test func automaticCheckStaysSilentOnFailureButPersistsThrottle() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = StubUpdateTransport(releaseFailure: .init(.network))
        let center = makeCenter(
            transport: transport,
            defaults: defaults.defaults,
            now: { now }
        )

        await center.checkAutomaticallyIfDue()

        #expect(center.phase == .idle)
        #expect(!center.isPanelPresented)
        #expect(center.lastCheckSucceeded == false)
        #expect(center.lastCheckDate == now)
        #expect(await transport.releaseFetchCount == 1)
    }

    @Test func manualFailureShowsRetryPanel() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let transport = StubUpdateTransport(releaseFailure: .init(.invalidResponse))
        let center = makeCenter(transport: transport, defaults: defaults.defaults)

        #expect(await center.checkForUpdates(manual: true) == false)

        #expect(center.isPanelPresented)
        if case .failed(let failure) = center.phase {
            #expect(failure.kind == .invalidResponse)
        } else {
            Issue.record("Expected failed phase")
        }
    }

    @Test func invalidCurrentVersionIsSilentAutomaticallyAndExplicitManually() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let transport = StubUpdateTransport()
        let center = makeCenter(
            transport: transport,
            defaults: defaults.defaults,
            version: "not-a-version"
        )

        #expect(await center.checkForUpdates(manual: false) == false)
        #expect(center.phase == .idle)
        #expect(!center.isPanelPresented)
        #expect(await transport.releaseFetchCount == 0)

        #expect(await center.checkForUpdates(manual: true) == false)
        #expect(center.isPanelPresented)
        if case .failed(let failure) = center.phase {
            #expect(failure.kind == .invalidCurrentVersion)
        } else {
            Issue.record("Expected invalidCurrentVersion failure")
        }
    }

    @Test func manualUpToDatePresentsResult() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let center = makeCenter(
            transport: StubUpdateTransport(),
            defaults: defaults.defaults
        )

        #expect(await center.checkForUpdates(manual: true))
        #expect(center.phase == .upToDate)
        #expect(center.isPanelPresented)
        #expect(center.lastCheckSucceeded == true)
    }

    @Test func manualRequestReusesAutomaticCheckAndSurfacesResult() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let transport = StubUpdateTransport(releaseDelay: .milliseconds(500))
        let center = makeCenter(transport: transport, defaults: defaults.defaults)

        let automatic = Task { await center.checkForUpdates(manual: false) }
        #expect(await waitUntil { await transport.releaseFetchCount == 1 })
        let manual = Task { await center.checkForUpdates(manual: true) }

        #expect(await automatic.value)
        #expect(await manual.value)
        #expect(await transport.releaseFetchCount == 1)
        #expect(center.phase == .upToDate)
        #expect(center.isPanelPresented)
    }

    @Test func availableReleaseActivatesAndReusesOpenPanel() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let recorder = PresentationRecorder()
        let transport = StubUpdateTransport(release: makeAvailableGitHubRelease())
        let center = makeCenter(
            transport: transport,
            defaults: defaults.defaults,
            activator: { recorder.activations += 1 }
        )

        #expect(await center.checkForUpdates(manual: true))
        #expect(center.isPanelPresented)
        #expect(recorder.activations == 0)

        center.panelDidDismiss()
        #expect(await center.checkForUpdates(manual: true))
        #expect(center.isPanelPresented)
        #expect(await transport.releaseFetchCount == 1)
    }

    @Test func blockedAutomaticUpdateWaitsForModalToClose() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let recorder = PresentationRecorder()
        let center = makeCenter(
            transport: StubUpdateTransport(release: makeAvailableGitHubRelease()),
            defaults: defaults.defaults,
            activator: { recorder.activations += 1 }
        )
        center.setPresentationBlocked(true)

        await center.checkAutomaticallyIfDue()

        #expect(!center.isPanelPresented)
        #expect(recorder.activations == 0)
        if case .available = center.phase {} else {
            Issue.record("Expected available phase")
        }

        center.setPresentationBlocked(false)
        #expect(center.isPanelPresented)
        #expect(recorder.activations == 1)
    }

    @Test func downloadReportsProgressAndReusesTask() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = StubUpdateTransport(
            release: makeAvailableGitHubRelease(),
            downloadDelay: .milliseconds(300)
        )
        let center = makeCenter(
            transport: transport,
            defaults: defaults.defaults,
            downloadsDirectory: directory
        )
        _ = await center.checkForUpdates(manual: true)
        center.panelDidDismiss()

        let first = Task { await center.downloadAndOpen() }
        #expect(await waitUntil {
            await transport.downloadCount == 1
        })
        #expect(await waitUntil {
            if case .downloading(_, let progress) = center.phase {
                return progress >= 0.49
            }
            return false
        })
        let second = Task { await center.downloadAndOpen() }

        #expect(await first.value)
        #expect(await second.value)
        #expect(await transport.downloadCount == 1)
        #expect(center.isPanelPresented)
        if case .downloaded(_, let fileURL, _, let opened, let quarantined) = center.phase {
            #expect(FileManager.default.fileExists(atPath: fileURL.path))
            #expect(opened)
            #expect(quarantined)
        } else {
            Issue.record("Expected downloaded phase")
        }
    }

    @Test func downloadCompletesInBackgroundAndPresentsAgain() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = StubUpdateTransport(
            release: makeAvailableGitHubRelease(),
            downloadDelay: .milliseconds(250)
        )
        let center = makeCenter(
            transport: transport,
            defaults: defaults.defaults,
            downloadsDirectory: directory
        )
        _ = await center.checkForUpdates(manual: true)

        let download = Task { await center.downloadAndOpen() }
        #expect(await waitUntil { await transport.downloadCount == 1 })
        center.panelDidDismiss()
        #expect(!center.isPanelPresented)

        #expect(await download.value)
        #expect(center.isPanelPresented)
        if case .downloaded = center.phase {} else {
            Issue.record("Expected downloaded phase")
        }
    }

    @Test func cancellingChecksumFetchCleansTemporaryFile() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let digest = String(repeating: "0", count: 64)
        let transport = StubUpdateTransport(
            release: makeAvailableGitHubRelease(includeChecksum: true),
            checksumData: Data("\(digest)  \(updateAssetName)\n".utf8),
            dataFetchDelay: .seconds(10)
        )
        let center = makeCenter(
            transport: transport,
            defaults: defaults.defaults,
            downloadsDirectory: directory
        )
        _ = await center.checkForUpdates(manual: true)

        let download = Task { await center.downloadAndOpen() }
        #expect(await waitUntil { await transport.downloadCount == 1 })
        #expect(await waitUntil {
            if let temporaryURL = await transport.downloadedTemporaryURL {
                return FileManager.default.fileExists(atPath: temporaryURL.path)
            }
            return false
        })

        center.cancelDownload()
        #expect(await download.value == false)
        if case .available(let release) = center.phase {
            #expect(release.tagName == "v1.2.0")
            #expect(release.checksumAsset != nil)
        } else {
            Issue.record("Expected available phase after cancellation")
        }
        if let temporaryURL = await transport.downloadedTemporaryURL {
            #expect(!FileManager.default.fileExists(atPath: temporaryURL.path))
        }
    }

    @Test func checksumMismatchDeletesDownloadAndBlocksOpening() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wrongDigest = String(repeating: "0", count: 64)
        let recorder = PresentationRecorder()
        let transport = StubUpdateTransport(
            release: makeAvailableGitHubRelease(includeChecksum: true),
            checksumData: Data("\(wrongDigest)  \(updateAssetName)\n".utf8)
        )
        let center = makeCenter(
            transport: transport,
            defaults: defaults.defaults,
            downloadsDirectory: directory,
            opener: { url in
                recorder.openedURLs.append(url)
                return true
            }
        )
        _ = await center.checkForUpdates(manual: true)

        #expect(await center.downloadAndOpen() == false)
        #expect(recorder.openedURLs.isEmpty)
        if case .downloadFailed(_, let failure) = center.phase {
            #expect(failure.kind == .checksumMismatch)
        } else {
            Issue.record("Expected checksumMismatch")
        }
        if let temporaryURL = await transport.downloadedTemporaryURL {
            #expect(!FileManager.default.fileExists(atPath: temporaryURL.path))
        }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty == true)
    }

    @Test func quarantineFailureKeepsFileButBlocksAutomaticOpen() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = PresentationRecorder()
        let quarantineAttempts = Counter()
        let center = makeCenter(
            transport: StubUpdateTransport(release: makeAvailableGitHubRelease()),
            defaults: defaults.defaults,
            downloadsDirectory: directory,
            quarantineWriter: { _, _, _ in
                quarantineAttempts.value += 1
                if quarantineAttempts.value == 1 {
                    throw TestError()
                }
            },
            opener: { url in
                recorder.openedURLs.append(url)
                return true
            }
        )
        _ = await center.checkForUpdates(manual: true)

        #expect(await center.downloadAndOpen())
        #expect(recorder.openedURLs.isEmpty)
        if case .downloaded(_, let fileURL, _, let opened, let quarantined) = center.phase {
            #expect(FileManager.default.fileExists(atPath: fileURL.path))
            #expect(!opened)
            #expect(!quarantined)
            #expect(center.retryOpeningDownloadedFile())
            #expect(recorder.openedURLs == [fileURL])
            if case .downloaded(_, _, _, let retryOpened, let retryQuarantined) = center.phase {
                #expect(retryOpened)
                #expect(retryQuarantined)
            } else {
                Issue.record("Expected downloaded phase after retry")
            }
        } else {
            Issue.record("Expected downloaded phase")
        }
    }

    @Test func automaticChecksAreThrottledForTwentyFourHours() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let transport = StubUpdateTransport()
        let center = makeCenter(
            transport: transport,
            defaults: defaults.defaults,
            now: { clock.now }
        )

        await center.checkAutomaticallyIfDue()
        #expect(await transport.releaseFetchCount == 1)

        clock.now.addTimeInterval(23 * 60 * 60)
        await center.checkAutomaticallyIfDue()
        #expect(await transport.releaseFetchCount == 1)

        clock.now.addTimeInterval(2 * 60 * 60)
        await center.checkAutomaticallyIfDue()
        #expect(await transport.releaseFetchCount == 2)
    }

    @Test func manualRetryAfterFailedCheckCanFindUpdate() async throws {
        let defaults = try makeDefaults()
        defer { removeDefaults(defaults) }
        let transport = RateLimitedUpdateTransport(
            release: makeAvailableGitHubRelease()
        )
        let center = makeCenter(transport: transport, defaults: defaults.defaults)

        await center.checkForUpdates(manual: true)
        if case .failed = center.phase {} else {
            Issue.record("Expected first manual check to fail")
        }

        let succeeded = await center.checkForUpdates(manual: true)
        #expect(succeeded)
        #expect(await transport.releaseFetchCount == 2)
        if case .available(let release) = center.phase {
            #expect(release.version.displayString == "1.2.0")
        } else {
            Issue.record("Expected retry to find an available release")
        }
    }
}

private let updateAssetName = "Hosts-Manager-1.2.0-arm64.dmg"
private let checksumAssetName = "\(updateAssetName).sha256"

private func asset(
    _ name: String,
    url: String? = nil
) -> GitHubRelease.Asset {
    GitHubRelease.Asset(
        name: name,
        browserDownloadURL: url ?? "https://example.com/\(name)",
        size: 1024
    )
}

private func makeGitHubRelease(
    tag: String = "v1.2.0",
    name: String = "Hosts Manager 1.2.0",
    draft: Bool = false,
    prerelease: Bool = false,
    htmlURL: String? = "https://github.com/breeze-ev/hosts-manager/releases/tag/v1.2.0",
    assets: [GitHubRelease.Asset] = []
) -> GitHubRelease {
    GitHubRelease(
        tagName: tag,
        name: name,
        body: "Release notes",
        publishedAt: "2026-10-27T12:34:56Z",
        htmlURL: htmlURL,
        draft: draft,
        prerelease: prerelease,
        assets: assets
    )
}

private func makeAvailableGitHubRelease(includeChecksum: Bool = false) -> GitHubRelease {
    var assets = [asset(updateAssetName)]
    if includeChecksum {
        assets.append(asset(checksumAssetName))
    }
    return makeGitHubRelease(assets: assets)
}

private func makeUpdateRelease(checksumText: String? = nil) -> UpdateRelease {
    let download = UpdateAsset(
        name: updateAssetName,
        url: URL(string: "https://example.com/\(updateAssetName)")!,
        size: 8
    )
    return UpdateRelease(
        tagName: "v1.2.0",
        version: AppVersion("1.2.0")!,
        title: "Hosts Manager 1.2.0",
        releaseNotes: "Release notes",
        publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
        pageURL: URL(string: "https://github.com/breeze-ev/hosts-manager/releases/tag/v1.2.0")!,
        downloadAsset: download,
        checksumAsset: checksumText.map { _ in
            UpdateAsset(
                name: checksumAssetName,
                url: URL(string: "https://example.com/\(checksumAssetName)")!,
                size: 80
            )
        }
    )
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("hosts-manager-update-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func makeDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = "hosts-manager-update-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    return (defaults, suiteName)
}

private func removeDefaults(_ value: (defaults: UserDefaults, suiteName: String)) {
    value.defaults.removePersistentDomain(forName: value.suiteName)
}

@MainActor
private func makeCenter(
    transport: UpdateTransport,
    defaults: UserDefaults,
    version: String? = "0.1.0",
    downloadsDirectory: URL? = nil,
    now: @escaping () -> Date = Date.init,
    quarantineWriter: @escaping (URL, URL, URL) throws -> Void = { _, _, _ in },
    opener: @escaping @MainActor (URL) -> Bool = { _ in true },
    activator: @escaping @MainActor () -> Void = {},
    revealer: @escaping @MainActor (URL) -> Void = { _ in }
) -> UpdateCenter {
    UpdateCenter(
        currentVersionString: version,
        currentBuildNumber: "1",
        transport: transport,
        defaults: defaults,
        now: now,
        downloadsDirectory: downloadsDirectory,
        automaticChecksEnabled: true,
        quarantineWriter: quarantineWriter,
        opener: opener,
        activator: activator,
        revealer: revealer
    )
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(3),
    _ predicate: @escaping @MainActor () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await predicate() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await predicate()
}

private actor StubUpdateTransport: UpdateTransport {
    private let release: GitHubRelease?
    private let releaseFailure: UpdateFailure?
    private let releaseDelay: Duration
    private let checksumData: Data?
    private let dataFetchDelay: Duration
    private let downloadDelay: Duration

    private(set) var releaseFetchCount = 0
    private(set) var dataFetchCount = 0
    private(set) var downloadCount = 0
    private(set) var downloadedTemporaryURL: URL?

    init(
        release: GitHubRelease? = nil,
        releaseFailure: UpdateFailure? = nil,
        releaseDelay: Duration = .zero,
        checksumData: Data? = nil,
        dataFetchDelay: Duration = .zero,
        downloadDelay: Duration = .zero
    ) {
        self.release = release
        self.releaseFailure = releaseFailure
        self.releaseDelay = releaseDelay
        self.checksumData = checksumData
        self.dataFetchDelay = dataFetchDelay
        self.downloadDelay = downloadDelay
    }

    func fetchLatestRelease() async throws -> GitHubRelease? {
        releaseFetchCount += 1
        if releaseDelay > .zero {
            try await Task.sleep(for: releaseDelay)
        }
        if let releaseFailure {
            throw releaseFailure
        }
        return release
    }

    func fetchData(from url: URL) async throws -> Data {
        dataFetchCount += 1
        if dataFetchDelay > .zero {
            try await Task.sleep(for: dataFetchDelay)
        }
        guard let checksumData else {
            throw URLError(.fileDoesNotExist)
        }
        return checksumData
    }

    func download(
        from url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        downloadCount += 1
        progress(0.5)
        if downloadDelay > .zero {
            try await Task.sleep(for: downloadDelay)
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hosts-manager-update-\(UUID().uuidString).dmg")
        try Data("test dmg".utf8).write(to: fileURL)
        downloadedTemporaryURL = fileURL
        progress(1)
        return fileURL
    }
}

@MainActor
private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class Counter {
    var value = 0

    func increment() {
        value += 1
    }
}

private final class RateLimitedUpdateTransport: UpdateTransport, @unchecked Sendable {
    private let release: GitHubRelease
    private var firstFetchCount: Int
    private var secondFetchCount: Int

    init(release: GitHubRelease) {
        self.release = release
        firstFetchCount = 0
        secondFetchCount = 0
    }

    var releaseFetchCount: Int {
        get async {
            firstFetchCount + secondFetchCount
        }
    }

    nonisolated func fetchLatestRelease() async throws -> GitHubRelease? {
        if firstFetchCount == 0 {
            firstFetchCount += 1
            throw UpdateFailure(.network, detail: "HTTP 403")
        }
        secondFetchCount += 1
        return release
    }

    nonisolated func fetchData(from url: URL) async throws -> Data {
        throw URLError(.fileDoesNotExist)
    }

    nonisolated func download(
        from url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        throw URLError(.fileDoesNotExist)
    }
}

@MainActor
private final class PresentationRecorder {
    var activations = 0
    var openedURLs: [URL] = []
}

private struct TestError: Error {}
