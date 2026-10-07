import Foundation
import Testing
@testable import Burnbar

extension BurnbarConfiguration {
    static var sample: Self {
        Self(profiles: [
            .init(id: "claude", provider: .claude, name: "Claude", indicator: "C", home: "~/.claude", enabled: false),
            .init(id: "private", provider: .codex, name: "Private", indicator: "P", home: "~/.codex", enabled: true),
            .init(id: "work", provider: .codex, name: "Work", indicator: "W", home: "~/.codex-business", enabled: true)
        ])
    }
}

struct ProfileSettingsTests {
    @Test
    @MainActor
    func freshConfigurationStaysEmptyWithoutCredentialReads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        #expect(try file.load().profiles.isEmpty)
        let store = QuotaSnapshotStore(configurationURL: file.url, codexRefresher: { _ in
            Issue.record("An empty configuration must not read credentials")
            return .failed(.noCredential)
        })
        store.reloadConfiguration()
        await store.refresh()
        #expect(store.providers.isEmpty)
    }

    @Test
    @MainActor
    func addingEditingAndRemovingPersistWithoutTouchingCredentials() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        let store = QuotaSnapshotStore(configurationURL: file.url)
        var profile = BurnbarConfiguration.sample.profiles[1]
        profile.color = "#123456"
        #expect(store.saveProfile(profile))
        #expect(try file.load().profiles == [profile])
        #expect(store.providers.first?.accent == .custom(hex: "#123456"))
        let original = profile
        profile.name = "Renamed"
        profile.indicator = "R"
        profile.color = "#ABCDEF"
        #expect(store.saveProfile(profile, replacing: original))
        #expect(try file.load().profiles == [profile])
        #expect(store.providers.first?.indicator == "R")
        #expect(store.removeProfile(profile))
        #expect(try file.load().profiles.isEmpty)
        #expect(store.providers.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("auth.json").path))
    }

    @Test
    @MainActor
    func savesPreserveExternalEditsAndRejectConflictingProfileChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        var config = BurnbarConfiguration.sample
        try file.save(config)
        let store = QuotaSnapshotStore(configurationURL: file.url)
        store.reloadConfiguration()
        let original = config.profiles[1]
        config.refreshIntervalMinutes = 30
        config.profiles[2].name = "External work name"
        try file.save(config)
        var edited = original
        edited.name = "My private name"
        #expect(store.saveProfile(edited, replacing: original))
        #expect(try file.load().refreshIntervalMinutes == 30)
        #expect(try file.load().profiles[2].name == "External work name")
        config = try file.load()
        config.profiles[1].name = "External private name"
        try file.save(config)
        #expect(!store.saveProfile(original, replacing: edited))
        #expect(!store.removeProfile(edited))
        #expect(store.configurationError != nil)
        #expect(try file.load().profiles[1].name == "External private name")
    }

    @Test
    @MainActor
    func invalidAndDuplicateSourcesDoNotModifyTheConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ConfigurationFile(url: directory.appendingPathComponent("config.json"))
        let store = QuotaSnapshotStore(configurationURL: file.url)
        let profile = BurnbarConfiguration.sample.profiles[1]
        #expect(store.saveProfile(profile))
        let duplicate = BurnbarConfiguration.Profile(id: "duplicate", provider: .codex, name: "Duplicate", indicator: "D", home: profile.homeURL.path, enabled: true)
        #expect(!store.saveProfile(duplicate))
        var invalid = profile
        invalid.indicator = "LONG"
        #expect(!store.saveProfile(invalid, replacing: profile))
        #expect(try file.load().profiles == [profile])
    }
}
