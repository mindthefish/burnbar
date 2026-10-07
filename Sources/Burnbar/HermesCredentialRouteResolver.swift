import Foundation

struct HermesCredentialRouteResolver {
    enum CodexSelection: Equatable {
        case credentialID(String)
        case primaryCredential
    }

    let fileURL: URL

    func activeCodexCredentialID() throws -> String? {
        guard case let .credentialID(credentialID) = try codexSelection() else {
            return nil
        }
        return credentialID
    }

    func codexSelection() throws -> CodexSelection? {
        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(whereSeparator: \ .isNewline)
            .map(String.init)

        guard let provider = activeProvider(in: lines) else {
            return nil
        }

        if provider == "openai-codex" {
            return .primaryCredential
        }

        guard provider.hasPrefix("credential-route:"),
              let route = credentialRoute(
                  named: String(provider.dropFirst("credential-route:".count)),
                  in: lines
              ),
              route.provider == "openai-codex"
        else {
            return nil
        }
        return .credentialID(route.credentialID)
    }

    private func activeProvider(in lines: [String]) -> String? {
        guard let modelIndex = lines.firstIndex(where: { $0 == "model:" }) else {
            return nil
        }

        for line in lines.dropFirst(modelIndex + 1) {
            guard line.hasPrefix("  ") else {
                break
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("provider:") else {
                continue
            }
            return value(after: "provider:", in: trimmed)
        }

        return nil
    }

    private func credentialRoute(named routeName: String, in lines: [String]) -> CredentialRoute? {
        guard let routesIndex = lines.firstIndex(where: { $0 == "credential_routes:" }),
              let routeIndex = lines.dropFirst(routesIndex + 1).firstIndex(where: { $0 == "  \(routeName):" })
        else {
            return nil
        }

        var provider: String?
        var credentialID: String?
        for line in lines.dropFirst(routeIndex + 1) {
            guard line.hasPrefix("    ") else {
                break
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("provider:") {
                provider = value(after: "provider:", in: trimmed)
            } else if trimmed.hasPrefix("credential:") {
                credentialID = value(after: "credential:", in: trimmed)
            }
        }

        guard let provider, let credentialID, !credentialID.isEmpty else {
            return nil
        }
        return CredentialRoute(provider: provider, credentialID: credentialID)
    }

    private func value(after key: String, in line: String) -> String {
        String(line.dropFirst(key.count))
            .trimmingCharacters(in: .whitespaces)
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
    }

    private struct CredentialRoute {
        let provider: String
        let credentialID: String
    }
}
