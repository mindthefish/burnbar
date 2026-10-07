import Foundation
import Testing
@testable import Burnbar

struct CodexCredentialStoreTests {
    @Test
    func missingAuthFileIsNoCredential() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("auth.json")
        #expect(try CodexCredentialStore(fileURL: url).credential() == nil)
    }

    @Test
    func missingAuthFileProducesTheCorrectRefreshFailure() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("auth.json")
        #expect(await CodexProviderRefresher().refresh(authFileURL: url) == .failed(.noCredential))
    }

    @Test
    func readsTheCredentialFromOneCodexProfileHome() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("auth.json")
        try """
        {
          "tokens": {
            "access_token": "test-private-token",
            "account_id": "private-account"
          }
        }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = CodexCredentialStore(fileURL: fileURL)

        #expect(try store.credential()?.accessToken == "test-private-token")
        #expect(try store.credential()?.accountID == "private-account")
    }

    @Test
    func returnsNoCredentialWhenTheProfileHasNoAccessToken() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("auth.json")
        try #"{"tokens":{"account_id":"private-account"}}"#.write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        #expect(try CodexCredentialStore(fileURL: fileURL).credential() == nil)
    }
}
