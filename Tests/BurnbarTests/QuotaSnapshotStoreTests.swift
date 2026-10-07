import Foundation
import os
import Testing
@testable import Burnbar

struct QuotaSnapshotStoreTests {
    @Test
    @MainActor
    func recordsEachResponseTimeBeforeSlowerProfilesFinish() async {
        let clock = OSAllocatedUnfairLock(initialState: (time: 100.0, reads: 0))
        let store = QuotaSnapshotStore(configuration: .sample, codexRefresher: { url in
            if url.path.contains("business") {
                while clock.withLock({ $0.reads }) == 0 { await Task.yield() }
                clock.withLock { $0.time = 200 }
            }
            return ProviderRefreshResult(snapshot: QuotaSnapshot(state: .available, windows: [QuotaWindow(label: "5h", usedPercentage: 20, resetsAt: nil)]))
        }, now: {
            clock.withLock { value in
                value.reads += 1
                return Date(timeIntervalSince1970: value.time)
            }
        })
        await store.refresh()
        #expect(store.providers[0].lastSuccessfulUpdate == Date(timeIntervalSince1970: 100))
        #expect(store.providers[1].lastSuccessfulUpdate == Date(timeIntervalSince1970: 200))
        #expect(store.lastUpdated == Date(timeIntervalSince1970: 100))
    }

    @Test
    @MainActor
    func duplicateSourcesFetchOnceAndReloadingUnchangedConfigPreservesDataAge() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        let first = BurnbarConfiguration.Profile(id: "one", provider: .codex, name: "One", indicator: "O", home: "/fake", enabled: true)
        let second = BurnbarConfiguration.Profile(id: "two", provider: .codex, name: "Two", indicator: "T", home: "/fake/../fake", enabled: true)
        let config = BurnbarConfiguration(profiles: [first, second])
        try file.save(config)
        let count = OSAllocatedUnfairLock(initialState: 0)
        let store = QuotaSnapshotStore(configuration: config, configurationURL: file.url, codexRefresher: { _ in
            count.withLock { $0 += 1 }
            return ProviderRefreshResult(snapshot: QuotaSnapshot(state: .available, windows: [QuotaWindow(label: "5h", usedPercentage: 20, resetsAt: nil)]))
        }, now: { Date(timeIntervalSince1970: 100) })
        await store.refresh()
        #expect(count.withLock { $0 } == 1)
        #expect(store.providers.count == 2)
        #expect(store.providers.allSatisfy { $0.lastSuccessfulUpdate == Date(timeIntervalSince1970: 100) })
        store.reloadConfiguration()
        #expect(count.withLock { $0 } == 1)
        #expect(store.lastUpdated == Date(timeIntervalSince1970: 100))
    }

    private var allProfiles: BurnbarConfiguration {
        var configuration = BurnbarConfiguration.sample
        configuration.profiles[0].enabled = true
        return configuration
    }

    @Test
    @MainActor
    func refreshAssignsEachCodexSnapshotToItsFixedIndicator() async {
        let store = QuotaSnapshotStore(
            configuration: allProfiles,
            codexRefresher: { authFileURL in
                switch authFileURL.path {
                case NSHomeDirectory() + "/.codex/auth.json":
                    return ProviderRefreshResult(snapshot: QuotaSnapshot(
                        state: .available,
                        windows: [QuotaWindow(label: "5h", usedPercentage: 42, resetsAt: .now)]
                    ))
                case NSHomeDirectory() + "/.codex-business/auth.json":
                    return ProviderRefreshResult(snapshot: QuotaSnapshot(
                        state: .available,
                        windows: [QuotaWindow(label: "7d", usedPercentage: 73, resetsAt: .now)]
                    ))
                default:
                    return .failed(.noCredential)
                }
            },
            claudeRefresher: { _ in .failed(.noCredential) }
        )

        await store.refresh()

        #expect(store.providers.map(\.indicator) == ["C", "P", "W"])
        #expect(store.providers[0].snapshot == .unavailable)
        #expect(store.providers[1].snapshot.windows.map(\.label) == ["5h"])
        #expect(store.providers[2].snapshot.windows.map(\.label) == ["7d"])
    }

    @Test
    @MainActor
    func failedRefreshRecordsAttemptWithoutInventingASuccessTime() async {
        let completionTime = Date(timeIntervalSince1970: 1_725_000_000)
        let store = QuotaSnapshotStore(
            configuration: allProfiles,
            codexRefresher: { _ in .failed(.noCredential) },
            claudeRefresher: { _ in .failed(.noCredential) },
            now: { completionTime }
        )

        await store.refresh()

        #expect(store.lastAttempted == completionTime)
        #expect(store.lastUpdated == nil)
    }

    @Test
    @MainActor
    func aFailedRefreshKeepsTheLastKnownWindowsInsteadOfBlankingThem() async {
        let succeed = OSAllocatedUnfairLock(initialState: true)
        let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 100))
        let store = QuotaSnapshotStore(
            configuration: allProfiles,
            codexRefresher: { _ in
                let ok = succeed.withLock { $0 }
                return ok
                    ? ProviderRefreshResult(snapshot: QuotaSnapshot(
                        state: .available,
                        windows: [QuotaWindow(label: "5h", usedPercentage: 42, resetsAt: .now)]
                    ))
                    : .failed(.rateLimited)
            },
            claudeRefresher: { _ in .failed(.noCredential) },
            now: { clock.withLock { $0 } }
        )

        await store.refresh()
        clock.withLock { $0 = Date(timeIntervalSince1970: 200) }
        succeed.withLock { $0 = false }
        await store.refresh()

        #expect(store.providers[1].lastSuccessfulUpdate == Date(timeIntervalSince1970: 100))
        #expect(store.lastUpdated == Date(timeIntervalSince1970: 100))
        #expect(store.lastAttempted == Date(timeIntervalSince1970: 200))
        #expect(store.providers[1].snapshot.state == .stale)
        #expect(store.providers[1].snapshot.windows.map(\.label) == ["5h"])
        #expect(store.providers[0].snapshot == .unavailable)
    }
}
