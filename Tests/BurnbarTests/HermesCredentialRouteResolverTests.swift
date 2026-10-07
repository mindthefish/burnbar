import Foundation
import Testing
@testable import Burnbar

struct HermesCredentialRouteResolverTests {
    @Test
    func resolvesTheActiveCodexCredentialIDFromTheModelRoute() throws {
        let fileURL = try writeConfig(
            """
            model:
              provider: credential-route:openai-codex-71e87e
            credential_routes:
              openai-codex-71e87e:
                provider: openai-codex
                credential: 71e87e
                display_name: codex-work
            """
        )

        #expect(try HermesCredentialRouteResolver(fileURL: fileURL).activeCodexCredentialID() == "71e87e")
    }

    @Test
    func rejectsAnActiveRouteForAnotherProvider() throws {
        let fileURL = try writeConfig(
            """
            model:
              provider: credential-route:anthropic-123456
            credential_routes:
              anthropic-123456:
                provider: anthropic
                credential: 123456
            """
        )

        #expect(try HermesCredentialRouteResolver(fileURL: fileURL).activeCodexCredentialID() == nil)
    }

    @Test
    func identifiesADirectOpenAICodexProvider() throws {
        let fileURL = try writeConfig(
            """
            model:
              provider: openai-codex
            """
        )

        #expect(try HermesCredentialRouteResolver(fileURL: fileURL).codexSelection() == .primaryCredential)
    }

    private func writeConfig(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("config.yaml")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
