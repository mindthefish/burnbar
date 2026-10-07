import Foundation
import SwiftUI

@MainActor
final class QuotaSnapshotStore: ObservableObject {
    typealias CodexRefresher = @Sendable (URL) async -> ProviderRefreshResult
    typealias ClaudeRefresher = @Sendable (_ force: Bool) async -> ProviderRefreshResult

    @Published private(set) var providers: [ProviderQuotaSnapshot]
    @Published private(set) var configuration: BurnbarConfiguration
    @Published private(set) var configurationError: String?
    /// Oldest success among displayed data; each card retains its own timestamp.
    var lastUpdated: Date? { providers.compactMap(\.lastSuccessfulUpdate).min() }
    @Published private(set) var lastAttempted: Date?
    @Published private(set) var isRefreshing = false

    var activeProfiles: [BurnbarConfiguration.Profile] { configuration.profiles.filter(\.enabled) }
    private let file: ConfigurationFile
    private let codexRefresher: CodexRefresher?
    private let claudeRefresher: ClaudeRefresher?
    private let now: @Sendable () -> Date
    private var codexRefreshers: [String: CodexProviderRefresher] = [:]
    private var claudeRefreshers: [String: ClaudeProviderRefresher] = [:]
    private var refreshTask: Task<Void, Never>?
    private var generation = 0

    init(
        configuration: BurnbarConfiguration = .defaults,
        configurationURL: URL = ConfigurationFile.defaultURL,
        codexRefresher: CodexRefresher? = nil,
        claudeRefresher: ClaudeRefresher? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        providers = configuration.profiles.filter(\.enabled).map(\.emptySnapshot)
        file = ConfigurationFile(url: configurationURL)
        self.codexRefresher = codexRefresher
        self.claudeRefresher = claudeRefresher
        self.now = now
    }

    deinit { refreshTask?.cancel() }

    func reloadConfiguration() {
        do {
            apply(try file.load())
            configurationError = nil
        } catch { configurationError = error.localizedDescription }
    }

    func setEnabled(_ enabled: Bool, profileID: String) {
        // Reload before editing so menu changes do not overwrite external edits.
        saveConfiguration { updated in
            guard let index = updated.profiles.firstIndex(where: { $0.id == profileID }) else { return }
            updated.profiles[index].enabled = enabled
        }
    }

    func setRefreshInterval(_ minutes: Int) {
        saveConfiguration { $0.refreshIntervalMinutes = minutes }
    }

    @discardableResult
    func saveProfile(_ profile: BurnbarConfiguration.Profile, replacing original: BurnbarConfiguration.Profile? = nil) -> Bool {
        saveConfiguration { updated in
            if updated.profiles.contains(where: {
                $0.id != profile.id && $0.provider == profile.provider
                    && $0.homeURL.standardizedFileURL == profile.homeURL.standardizedFileURL
            }) {
                throw ConfigurationError.invalid("This provider folder has already been added.")
            }
            if let original {
                guard profile.id == original.id,
                      let index = updated.profiles.firstIndex(where: { $0.id == original.id }),
                      updated.profiles[index] == original else {
                    throw ConfigurationError.invalid("This subscription changed in the configuration. Reload it before editing.")
                }
                updated.profiles[index] = profile
            } else {
                updated.profiles.append(profile)
            }
        }
    }

    @discardableResult
    func removeProfile(_ profile: BurnbarConfiguration.Profile) -> Bool {
        saveConfiguration { updated in
            guard let index = updated.profiles.firstIndex(where: { $0.id == profile.id }),
                  updated.profiles[index] == profile else {
                throw ConfigurationError.invalid("This subscription changed in the configuration. Reload it before removing.")
            }
            updated.profiles.remove(at: index)
        }
    }

    @discardableResult
    private func saveConfiguration(_ edit: (inout BurnbarConfiguration) throws -> Void) -> Bool {
        do {
            var updated = try file.load()
            try edit(&updated)
            try file.save(updated)
            apply(updated)
            configurationError = nil
            return true
        } catch {
            configurationError = error.localizedDescription
            return false
        }
    }

    func openConfiguration() {
        do {
            if !FileManager.default.fileExists(atPath: file.url.path) {
                try file.save(configuration)
            }
            if !NSWorkspace.shared.open(file.url) {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
        } catch { configurationError = error.localizedDescription }
    }

    private func apply(_ updated: BurnbarConfiguration) {
        guard updated != configuration else { return }
        let wasRunning = refreshTask != nil
        stopRefreshing()
        generation += 1
        let oldProfiles = activeProfiles
        let oldProviders = providers
        let retained = Dictionary(uniqueKeysWithValues: zip(oldProfiles, oldProviders).map { ($0.id, ($0, $1)) })
        configuration = updated
        providers = activeProfiles.map { profile in
            if let (old, snapshot) = retained[profile.id], old == profile { return snapshot }
            return profile.emptySnapshot
        }
        let activeClaudePaths = Set(activeProfiles.filter { $0.provider == .claude }.map { $0.homeURL.path })
        claudeRefreshers = claudeRefreshers.filter { activeClaudePaths.contains($0.key) }
        let activeCodexPaths = Set(activeProfiles.filter { $0.provider == .codex }.map { $0.homeURL.standardizedFileURL.path })
        codexRefreshers = codexRefreshers.filter { activeCodexPaths.contains($0.key) }
        lastAttempted = nil
        if wasRunning { startRefreshing() }
    }

    func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            // A replaced configuration waits for the previous network operation to finish.
            while !Task.isCancelled, self?.isRefreshing == true {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            await self?.refresh(force: false)
            while !Task.isCancelled {
                guard let minutes = self?.configuration.refreshIntervalMinutes else { return }
                do { try await Task.sleep(for: .seconds(minutes * 60)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await self?.refresh(force: false)
            }
        }
    }

    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Only the explicit access action supplies a profile ID; ordinary refreshes never prompt.
    func refresh(force: Bool = true, authorizing profileID: String? = nil) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let refreshGeneration = generation
        let profiles = activeProfiles
        let codex = codexRefresher
        let injectedClaude = claudeRefresher
        for profile in profiles where profile.provider == .claude {
            let home = profile.homeURL
            if claudeRefreshers[home.path] == nil { claudeRefreshers[home.path] = ClaudeProviderRefresher(home: home) }
        }
        for profile in profiles where profile.provider == .codex {
            let path = profile.homeURL.standardizedFileURL.path
            if codexRefreshers[path] == nil { codexRefreshers[path] = CodexProviderRefresher() }
        }
        let codexActors = codexRefreshers
        let claude = claudeRefreshers
        let completionTime = now
        // Profiles may share a source in a hand-edited config. Fetch it once per cycle.
        func sourceKey(_ profile: BurnbarConfiguration.Profile) -> String {
            // Claude Keychain service names hash the configured path itself.
            profile.provider.rawValue + ":" + (profile.provider == .claude
                ? profile.homeURL.path : profile.homeURL.standardizedFileURL.path)
        }
        let grouped = Dictionary(grouping: profiles, by: sourceKey)
        let results = await withTaskGroup(of: (String, ProviderRefreshResult, Date).self) { group in
            for (key, matching) in grouped {
                guard let profile = matching.first else { continue }
                let authorizationID = matching.first(where: { $0.id == profileID })?.id
                let claudeActor = claude[profile.homeURL.path]
                group.addTask {
                    let result: ProviderRefreshResult
                    switch profile.provider {
                    case .codex:
                        let authURL = profile.homeURL.appendingPathComponent("auth.json")
                        if let codex { result = await codex(authURL) }
                        else if let refresher = codexActors[profile.homeURL.standardizedFileURL.path] {
                            result = await refresher.refresh(authFileURL: authURL, force: force)
                        } else { result = .failed(.noCredential) }
                    case .claude:
                        if let injectedClaude { result = await injectedClaude(force) }
                        else if let refresher = claudeActor {
                            result = await refresher.refresh(force: force, allowInteraction: authorizationID != nil)
                        } else { result = .failed(.noCredential) }
                    }
                    return (key, result, completionTime())
                }
            }
            var collected: [String: (result: ProviderRefreshResult, date: Date)] = [:]
            for await (key, result, date) in group { collected[key] = (result, date) }
            return collected
        }
        guard generation == refreshGeneration, !Task.isCancelled else { return }
        providers = providers.enumerated().map { index, provider in
            let completed = results[sourceKey(profiles[index])]
            let result = completed?.result ?? .failed(.unexpectedResponse)
            return ProviderQuotaSnapshot(
                indicator: provider.indicator, displayName: provider.displayName,
                accent: provider.accent, snapshot: provider.snapshot.superseded(by: result.snapshot),
                failure: result.failure,
                lastSuccessfulUpdate: result.snapshot.state == .available
                    ? completed?.date : provider.lastSuccessfulUpdate
            )
        }
        lastAttempted = profiles.isEmpty ? nil : now()
    }
}
