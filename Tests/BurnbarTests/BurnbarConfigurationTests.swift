import Foundation
import os
import Testing
@testable import Burnbar

struct BurnbarConfigurationTests {
    @Test
    func omittedIntervalUsesFiveMinutes() throws {
        let config = try JSONDecoder().decode(BurnbarConfiguration.self, from: Data(#"{"profiles":[]}"#.utf8))
        #expect(config.refreshIntervalMinutes == 5)
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
