import Foundation
import os
import Testing
@testable import Burnbar

struct BurnbarConfigurationTests {
    @Test
    @MainActor
    func olderConfigurationsKeepExtraProfilesEditableWithoutChangingTheFileOnLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        var legacy = BurnbarConfiguration.sample
        legacy.profiles[0].enabled = true
        legacy.profiles.append(.init(id: "extra", provider: .codex, name: "Extra", indicator: "E", home: "/fake-extra", enabled: true))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalData = try JSONEncoder().encode(legacy)
        try originalData.write(to: file.url)
        let loaded = try file.load()
        #expect(loaded.profiles.map(\.id) == legacy.profiles.map(\.id))
        #expect(loaded.profiles.map(\.enabled) == [true, true, true, false])
        #expect(try Data(contentsOf: file.url) == originalData)
        let store = QuotaSnapshotStore(configurationURL: file.url)
        store.reloadConfiguration()
        #expect(store.configuration.profiles.count == 4)
        #expect(store.configurationError == nil)
        store.setEnabled(false, profileID: legacy.profiles[0].id)
        store.setEnabled(true, profileID: "extra")
        #expect(store.activeProfiles.count == 3)
        #expect(store.configuration.profiles.last?.enabled == true)
        #expect(store.configurationError == nil)
    }

    @Test
    @MainActor
    func activeLimitAllowsStoredProfilesAndReorderingKeepsQuotaIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        var config = BurnbarConfiguration.sample
        config.profiles[0].enabled = true
        config.profiles[1].quotaColors = .standard
        config.profiles.append(.init(id: "extra", provider: .codex, name: "Extra", indicator: "E", home: "/fake-extra", enabled: false))
        try file.save(config)
        let store = QuotaSnapshotStore(configuration: config, configurationURL: file.url,
                                      codexRefresher: { _ in
            ProviderRefreshResult(snapshot: QuotaSnapshot(state: .available, windows: [
                QuotaWindow(label: "5h", usedPercentage: 42, resetsAt: nil)
            ]))
        }, claudeRefresher: { _ in .failed(.noCredential) })
        await store.refresh()
        let originalProviders = store.providers
        store.setEnabled(true, profileID: "extra")
        #expect(store.activeProfiles.count == 3)
        #expect(store.configurationError != nil)
        #expect(try file.load() == config)
        let moving = config.profiles[1]
        let target = config.profiles[2]
        #expect(store.moveProfile(id: moving.id, to: target.id))
        #expect(store.configuration.profiles.map(\.id) == [config.profiles[0].id, target.id, moving.id, "extra"])
        #expect(store.providers == [originalProviders[0], originalProviders[2], originalProviders[1]])
        #expect(store.providers[2].quotaColors == .standard)
        #expect(try file.load() == store.configuration)
        #expect(store.moveProfile(id: moving.id, to: config.profiles[0].id))
        #expect(store.configuration.profiles.first?.id == moving.id)
        store.setEnabled(false, profileID: moving.id)
        store.setEnabled(true, profileID: "extra")
        #expect(store.activeProfiles.count == 3)
        #expect(store.configurationError == nil)
        #expect(try file.load().profiles.last?.enabled == true)
    }

    @Test
    func fullQuotaColorDefinesIdentityWhileVariableColorsAreEnabled() {
        var profile = BurnbarConfiguration.sample.profiles[1]
        profile.color = "#123456"
        #expect(profile.accent == .custom(hex: "#123456"))
        profile.quotaColors = QuotaColors(full: "#00FF00", empty: "#FF0000")
        #expect(profile.accent == .custom(hex: "#00FF00"))
        #expect(profile.emptySnapshot.accent == .custom(hex: "#00FF00"))
        #expect(profile.fixedAccent == .custom(hex: "#123456"))
        profile.quotaColors?.full = "#0000FF"
        #expect(profile.accent == .custom(hex: "#0000FF"))
        profile.quotaColors = nil
        #expect(profile.accent == .custom(hex: "#123456"))
    }

    @Test
    func omittedIntervalUsesFiveMinutes() throws {
        let config = try JSONDecoder().decode(BurnbarConfiguration.self, from: Data(#"{"profiles":[]}"#.utf8))
        #expect(config.refreshIntervalMinutes == 5)
    }

    @Test
    func oldConfigurationOmitsSymbol() throws {
        let data = Data(#"{"profiles":[{"id":"personal","provider":"codex","name":"Personal","indicator":"P","home":"~/.codex","enabled":true}]}"#.utf8)
        let config = try JSONDecoder().decode(BurnbarConfiguration.self, from: data).validated()
        #expect(config.profiles[0].symbol == nil)
        #expect(config.profiles[0].quotaColors == nil)
        let encoded = try JSONEncoder().encode(config)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("symbol"))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("quotaColors"))
    }

    @Test
    func persistsQuotaColorsAlongsideFixedColorAndRejectsInvalidEndpoints() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        var config = BurnbarConfiguration.sample
        try file.save(config)
        #expect(!String(decoding: try Data(contentsOf: file.url), as: UTF8.self).contains("quotaColors"))
        config.profiles[0].color = "#123456"
        config.profiles[0].quotaColors = QuotaColors(full: "#abcdef", empty: "#FF0000")
        try file.save(config)
        #expect(try file.load() == config)
        config.profiles[0].quotaColors?.full = "#GG0000"
        #expect(throws: ConfigurationError.self) { try config.validated() }
        config.profiles[0].quotaColors = QuotaColors(full: "#00FF00", empty: "red")
        #expect(throws: ConfigurationError.self) { try config.validated() }
    }

    @Test
    func persistsSymbolWithEmptyIndicatorAndOmitsUnsetSymbols() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        var config = BurnbarConfiguration.sample
        try file.save(config)
        #expect(!String(decoding: try Data(contentsOf: file.url), as: UTF8.self).contains("symbol"))
        config.profiles[0].symbol = .flame
        config.profiles[0].indicator = ""
        #expect(config.profiles[0].hasValidIndicator)
        try file.save(config)
        #expect(try file.load() == config)
        #expect(String(decoding: try Data(contentsOf: file.url), as: UTF8.self).contains(#""symbol": "flame.fill""#))
    }

    @Test
    func rejectsLongTextEvenWithSymbolAndEmptyTextWithoutSymbol() {
        var config = BurnbarConfiguration.sample
        config.profiles[0].symbol = .person
        config.profiles[0].indicator = "ABC"
        #expect(throws: ConfigurationError.self) { try config.validated() }
        config.profiles[0].symbol = nil
        config.profiles[0].indicator = ""
        #expect(!config.profiles[0].hasValidIndicator)
        #expect(throws: ConfigurationError.self) { try config.validated() }
        config.profiles[0].indicator = "A "
        #expect(!config.profiles[0].hasValidIndicator)
        #expect(throws: ConfigurationError.self) { try config.validated() }
    }

    @Test
    @MainActor
    func symbolReachesMenuBarAndSurvivesSuccessfulAndFailedRefresh() async {
        var config = BurnbarConfiguration.sample
        config.profiles = [config.profiles[1]]
        config.profiles[0].symbol = .briefcase
        config.profiles[0].quotaColors = .standard
        config.profiles[0].indicator = ""
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let store = QuotaSnapshotStore(configuration: config, codexRefresher: { _ in
            let call = calls.withLock { count in
                count += 1
                return count
            }
            return call == 1
                ? ProviderRefreshResult(snapshot: QuotaSnapshot(state: .available, windows: [
                    QuotaWindow(label: "5h", usedPercentage: 42, resetsAt: nil)
                ]))
                : .failed(.noCredential)
        })
        #expect(store.providers.first?.symbol == .briefcase)
        #expect(store.providers.first?.quotaColors == .standard)
        await store.refresh()
        #expect(store.providers.first?.symbol == .briefcase)
        #expect(store.providers.first?.quotaColors == .standard)
        #expect(MenuBarPresentation(providers: store.providers).indicators.first?.symbol == .briefcase)
        #expect(MenuBarPresentation(providers: store.providers).indicators.first?.quotaColors == .standard)
        await store.refresh()
        #expect(store.providers.first?.symbol == .briefcase)
        #expect(store.providers.first?.quotaColors == .standard)
        #expect(store.providers.first?.snapshot.state == .stale)
        #expect(MenuBarPresentation(providers: store.providers).indicators.first?.symbol == .briefcase)
        #expect(MenuBarPresentation(providers: store.providers).indicators.first?.quotaColors == .standard)
    }

    @Test
    func rejectsUnsafeIntervalsDuplicateIDsAndRelativeHomes() throws {
        var config = BurnbarConfiguration.sample
        config.refreshIntervalMinutes = 1
        #expect(throws: ConfigurationError.self) { try config.validated() }
        config = .sample
        config.profiles.append(config.profiles[0])
        #expect(throws: ConfigurationError.self) { try config.validated() }
        config = .sample
        config.profiles[0].home = "relative/path"
        #expect(throws: ConfigurationError.self) { try config.validated() }
    }

    @Test
    func persistsProfilesAndExpandsHomeWithoutReadingCredentials() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        #expect(try file.load() == .defaults)
        var config = BurnbarConfiguration.sample
        config.refreshIntervalMinutes = 30
        try file.save(config)
        #expect(try file.load() == config)
        #expect(config.profiles[0].homeURL.path == NSHomeDirectory() + "/.claude")
    }

    @Test
    @MainActor
    func disabledProfilesAreNeverRefreshedAndSourcesStayOrdered() async {
        let paths = OSAllocatedUnfairLock(initialState: [String]())
        let claudeCalls = OSAllocatedUnfairLock(initialState: 0)
        let store = QuotaSnapshotStore(
            configuration: .sample,
            codexRefresher: { url in
                paths.withLock { $0.append(url.path) }
                return .failed(.noCredential)
            },
            claudeRefresher: { _ in
                claudeCalls.withLock { $0 += 1 }
                return .failed(.noCredential)
            }
        )
        await store.refresh()
        #expect(claudeCalls.withLock { $0 } == 0)
        #expect(Set(paths.withLock { $0 }) == Set([
            NSHomeDirectory() + "/.codex/auth.json", NSHomeDirectory() + "/.codex-business/auth.json"
        ]))
        #expect(store.providers.map(\.indicator) == ["P", "W"])
    }

    @Test
    @MainActor
    func invalidReloadRetainsLastValidConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        var config = BurnbarConfiguration.sample
        config.profiles = []
        config.refreshIntervalMinutes = 15
        try file.save(config)
        let store = QuotaSnapshotStore(configurationURL: file.url)
        store.reloadConfiguration()
        #expect(store.providers.isEmpty)
        try Data("invalid".utf8).write(to: file.url)
        store.reloadConfiguration()
        #expect(store.configuration == config)
        #expect(store.configurationError != nil)
    }

    @Test
    @MainActor
    func configurationChangeDiscardsInFlightResults() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        let gate = RefreshGate()
        let store = QuotaSnapshotStore(configuration: .sample, configurationURL: file.url, codexRefresher: { _ in
            await gate.wait()
            return ProviderRefreshResult(snapshot: QuotaSnapshot(state: .available, windows: [
                QuotaWindow(label: "5h", usedPercentage: 42, resetsAt: nil)
            ]))
        })
        let task = Task { await store.refresh() }
        while await gate.count < 2 { await Task.yield() }
        var config = BurnbarConfiguration.sample
        config.profiles = []
        try file.save(config)
        store.reloadConfiguration()
        await gate.release()
        await task.value
        #expect(store.providers.isEmpty)
        #expect(store.lastUpdated == nil)
    }
}

private actor RefreshGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    var count: Int { continuations.count }
    func wait() async { await withCheckedContinuation { continuations.append($0) } }
    func release() {
        for continuation in continuations { continuation.resume() }
        continuations = []
    }
}
