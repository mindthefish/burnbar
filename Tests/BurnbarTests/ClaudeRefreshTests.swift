import Foundation
import Security
import Testing
@testable import Burnbar

struct ClaudeRefreshTests {
    @Test
    func preservesTheHighestUsedModelWindowsOwnReset() throws {
        let data = Data("""
        {
          "seven_day_opus": {"utilization": 95, "resets_at": "2026-08-28T14:25:00Z"},
          "seven_day_sonnet": {"utilization": 5, "resets_at": "2026-08-27T14:25:00Z"}
        }
        """.utf8)
        let snapshot = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data).quotaSnapshot

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows.first?.usedPercentage == 95)
        #expect(snapshot.windows.first?.resetsAt == ISO8601DateFormatter().date(from: "2026-08-28T14:25:00Z"))
    }

    @Test
    func selectsTheHighestValidModelWindowAndBreaksTiesByKey() throws {
        let data = Data("""
        {
          "seven_day": {"utilization": 101},
          "seven_day_invalid": {"utilization": 150},
          "seven_day_opus": {"utilization": 95, "resets_at": null},
          "seven_day_sonnet": {"utilization": 95, "resets_at": "2026-08-27T14:25:00Z"},
          "seven_day_low": {"utilization": -1}
        }
        """.utf8)
        let snapshot = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data).quotaSnapshot

        #expect(snapshot.windows.first?.usedPercentage == 95)
        #expect(snapshot.windows.first?.resetsAt == nil)
    }

    @Test
    func prefersTheValidExactWindowOverModelSpecificWindows() throws {
        let data = Data("""
        {
          "seven_day": {"utilization": 12, "resets_at": null},
          "seven_day_opus": {"utilization": 95, "resets_at": "2026-08-28T14:25:00Z"}
        }
        """.utf8)
        let snapshot = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data).quotaSnapshot

        #expect(snapshot.windows.first?.usedPercentage == 12)
        #expect(snapshot.windows.first?.resetsAt == nil)
    }

    @Test
    func readsNestedClaudeCodeOAuthCredential() {
        let data = """
        {
          "claudeAiOauth": {
            "accessToken": "test-claude-token"
          }
        }
        """.data(using: .utf8)!
        let store = ClaudeCredentialStore(keychainLookup: { _ in (data, errSecSuccess) }, fileReader: { _ in nil })

        #expect(store.credential()?.isUsable == true)
    }

    @Test
    func mapsClaudeUsageWindowsToQuotaSnapshot() throws {
        let data = """
        {
          "five_hour": {
            "utilization": 42,
            "resets_at": "2026-08-21T18:00:00Z"
          },
          "seven_day": {
            "utilization": 73,
            "resets_at": "2026-08-27T14:25:00Z"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)

        #expect(response.quotaSnapshot.windows.map(\.label) == ["5h", "7d"])
        #expect(response.quotaSnapshot.windows.map(\.usedPercentage) == [42, 73])
    }

    @Test
    func mapsWindowsWhoseResetTimestampsCarryFractionalSeconds() throws {
        let data = """
        {
          "five_hour": {
            "utilization": 21,
            "resets_at": "2026-08-22T02:00:00.115393+00:00"
          },
          "seven_day": {
            "utilization": 43,
            "resets_at": "2026-08-26T11:00:00.115416+00:00"
          },
          "seven_day_opus": null,
          "limits": []
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        let snapshot = response.quotaSnapshot

        #expect(snapshot.state == .available)
        #expect(snapshot.windows.map(\.label) == ["5h", "7d"])
        #expect(snapshot.windows.map(\.usedPercentage) == [21, 43])
    }

    @Test
    func keepsAWindowWhoseUtilizationIsKnownWithoutAResetTimestamp() throws {
        let data = """
        {
          "five_hour": {
            "utilization": 0,
            "resets_at": null
          },
          "seven_day": {
            "utilization": 43,
            "resets_at": "2026-08-26T11:00:00.115416+00:00"
          }
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data).quotaSnapshot

        #expect(snapshot.windows.map(\.label) == ["5h", "7d"])
        #expect(snapshot.windows[0].resetsAt == nil)
        #expect(snapshot.windows[0].usedPercentage == 0)
    }

    @Test
    func findsAnAccessTokenThatMovedToADifferentNestingLevel() {
        let data = """
        {
          "claudeAiOauth": {
            "tokens": { "accessToken": "nested-token" },
            "refreshToken": "must-not-be-used"
          }
        }
        """.data(using: .utf8)!
        let store = ClaudeCredentialStore(keychainLookup: { _ in (data, errSecSuccess) }, fileReader: { _ in nil })

        #expect(store.credential()?.accessToken == "nested-token")
    }

    @Test
    func neverMistakesARefreshTokenForAnAccessToken() {
        let data = """
        {
          "claudeAiOauth": { "refreshToken": "refresh-only" }
        }
        """.data(using: .utf8)!
        let store = ClaudeCredentialStore(keychainLookup: { _ in (data, errSecSuccess) }, fileReader: { _ in nil })

        #expect(store.credential() == nil)
    }

    @Test
    func treatsAnEmptyAccessTokenAsSignedOut() {
        let data = """
        {
          "claudeAiOauth": { "accessToken": "", "refreshToken": "r", "scopes": [] }
        }
        """.data(using: .utf8)!
        let store = ClaudeCredentialStore(keychainLookup: { _ in (data, errSecSuccess) }, fileReader: { _ in nil })

        guard case let .unreadable(keys, _, _) = store.lookup() else {
            Issue.record("expected an unreadable credential")
            return
        }
        #expect(keys == [ClaudeCredentialStore.signedOutDescription])
    }

    @Test
    func treatsANullAccessTokenAsSignedOut() {
        let data = """
        {
          "claudeAiOauth": { "accessToken": null }
        }
        """.data(using: .utf8)!
        let store = ClaudeCredentialStore(keychainLookup: { _ in (data, errSecSuccess) }, fileReader: { _ in nil })

        guard case let .unreadable(keys, _, _) = store.lookup() else {
            Issue.record("expected an unreadable credential")
            return
        }
        #expect(keys == [ClaudeCredentialStore.signedOutDescription])
    }

    @Test
    func prefersAValidCredentialFileWithoutReadingTheKeychain() {
        let file = """
        { "claudeAiOauth": { "accessToken": "file-token" } }
        """.data(using: .utf8)!
        let store = ClaudeCredentialStore(
            keychainLookup: { _ in
                Issue.record("must not read the Keychain when the file has a valid token")
                return (nil, errSecItemNotFound)
            },
            fileReader: { _ in file }
        )

        #expect(store.credential()?.accessToken == "file-token")
    }

    @Test
    func readsOnlyTheFileWhenCheckingForARotationWithACachedCredential() {
        let store = ClaudeCredentialStore(
            keychainLookup: { _, _ in
                Issue.record("a file-only rotation check must not read the Keychain")
                return (nil, errSecItemNotFound)
            },
            fileReader: { _ in nil }
        )

        #expect(store.credentialFromFile() == nil)
    }

    @Test
    func fallsBackToTheKeychainWhenTheFileHasNoUsableToken() {
        let file = """
        { "claudeAiOauth": { "accessToken": "" } }
        """.data(using: .utf8)!
        let keychain = """
        { "claudeAiOauth": { "accessToken": "keychain-token" } }
        """.data(using: .utf8)!
        let store = ClaudeCredentialStore(
            keychainLookup: { _ in (keychain, errSecSuccess) },
            fileReader: { _ in file }
        )

        #expect(store.credential()?.accessToken == "keychain-token")
    }

    @Test
    func prefersTheKeychainWhenTheFileTokenHasExpired() {
        let file = """
        { "claudeAiOauth": { "accessToken": "expired-file-token", "expiresAt": 0 } }
        """.data(using: .utf8)!
        let keychain = """
        { "claudeAiOauth": { "accessToken": "keychain-token" } }
        """.data(using: .utf8)!
        let store = ClaudeCredentialStore(
            keychainLookup: { _ in (keychain, errSecSuccess) },
            fileReader: { _ in file }
        )

        #expect(store.credential()?.accessToken == "keychain-token")
    }

    @Test
    func fallsBackToTheKeychainWhenTheFileIsAbsent() {
        let keychain = """
        { "claudeAiOauth": { "accessToken": "keychain-token" } }
        """.data(using: .utf8)!
        let store = ClaudeCredentialStore(
            keychainLookup: { _ in (keychain, errSecSuccess) },
            fileReader: { _ in nil }
        )

        #expect(store.credential()?.accessToken == "keychain-token")
    }

    @Test
    func resolvesTheCredentialFileFromTheProfileDirectory() {
        let home = URL(fileURLWithPath: "/Users/example/.claude-business", isDirectory: true)
        let file = """
        { "claudeAiOauth": { "accessToken": "file-token" } }
        """.data(using: .utf8)!
        let store = ClaudeCredentialStore(
            home: home,
            keychainLookup: { _, _ in
                Issue.record("must not read the Keychain when the profile file has a valid token")
                return (nil, errSecItemNotFound)
            },
            fileReader: { url in
                #expect(url == home.appendingPathComponent(".credentials.json"))
                return file
            }
        )

        #expect(store.credential()?.accessToken == "file-token")
    }

    @Test
    func usesClaudeCodesHashedKeychainServiceForCustomProfileDirectories() {
        let home = URL(fileURLWithPath: "/Users/example/.claude-business", isDirectory: true)
        let store = ClaudeCredentialStore(
            home: home,
            keychainLookup: { service, _ in
                #expect(service == "Claude Code-credentials-4cc0c487")
                return (nil, errSecItemNotFound)
            },
            fileReader: { _ in nil }
        )

        _ = store.lookup()
    }

    @Test
    func preventsKeychainUIForBackgroundLookupsAndAllowsItForExplicitActions() {
        let backgroundStore = ClaudeCredentialStore(
            keychainLookup: { _, allowInteraction in
                #expect(!allowInteraction)
                return (nil, errSecInteractionNotAllowed)
            },
            fileReader: { _ in nil }
        )
        let interactiveStore = ClaudeCredentialStore(
            keychainLookup: { _, allowInteraction in
                #expect(allowInteraction)
                return (nil, errSecUserCanceled)
            },
            fileReader: { _ in nil }
        )

        guard case .accessDenied(errSecInteractionNotAllowed) = backgroundStore.lookup() else {
            Issue.record("expected a background Keychain interaction failure")
            return
        }
        guard case .accessDenied(errSecUserCanceled) = interactiveStore.lookup(allowInteraction: true) else {
            Issue.record("expected an explicit-action Keychain result")
            return
        }
    }

    @Test
    func doesNotHideAKeychainInteractionFailureBehindAnExpiredCredentialFile() {
        let expiredFile = """
        { "claudeAiOauth": { "accessToken": "expired-file-token", "expiresAt": 0 } }
        """.data(using: .utf8)!
        let store = ClaudeCredentialStore(
            keychainLookup: { _, allowInteraction in
                #expect(allowInteraction)
                return (nil, errSecInteractionNotAllowed)
            },
            fileReader: { _ in expiredFile }
        )

        guard case .accessDenied(errSecInteractionNotAllowed) = store.lookup(allowInteraction: true) else {
            Issue.record("expected Keychain access to take precedence over an expired file token")
            return
        }
    }
}
