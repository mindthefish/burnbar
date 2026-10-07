import Foundation

struct BurnbarConfiguration: Codable, Equatable, Sendable {
    var refreshIntervalMinutes: Int = 5
    var profiles: [Profile]

    private enum CodingKeys: String, CodingKey { case refreshIntervalMinutes, profiles }

    init(refreshIntervalMinutes: Int = 5, profiles: [Profile]) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.profiles = profiles
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        refreshIntervalMinutes = try values.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? 5
        profiles = try values.decode([Profile].self, forKey: .profiles)
    }

    struct Profile: Codable, Equatable, Identifiable, Sendable {
        enum Provider: String, Codable, Sendable { case codex, claude }
        let id: String
        let provider: Provider
        var name: String
        var indicator: String
        var home: String
        var enabled: Bool
        var color: String? = nil

        var homeURL: URL {
            URL(fileURLWithPath: NSString(string: home).expandingTildeInPath, isDirectory: true)
        }

        var accent: ProviderQuotaSnapshot.Accent {
            if let color { return .custom(hex: color) }
            return provider == .claude ? .claude : (id == "work" ? .workOpenAI : .privateOpenAI)
        }

        var emptySnapshot: ProviderQuotaSnapshot {
            ProviderQuotaSnapshot(
                indicator: indicator, displayName: name,
                accent: accent,
                snapshot: .unavailable
            )
        }
    }

    static let defaults = BurnbarConfiguration(profiles: [])

    func validated() throws -> Self {
        guard (5...1440).contains(refreshIntervalMinutes) else {
            throw ConfigurationError.invalid("Refresh interval must be between 5 and 1440 minutes.")
        }
        guard Set(profiles.map(\.id)).count == profiles.count else {
            throw ConfigurationError.invalid("Profile IDs must be unique.")
        }
        for profile in profiles {
            if let color = profile.color {
                guard color.utf8.count == 7,
                      color.first == "#",
                      color.dropFirst().utf8.allSatisfy({
                          (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                      }) else {
                    throw ConfigurationError.invalid("Profile color must use the hex format #RRGGBB.")
                }
            }
            guard !profile.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (1...2).contains(profile.indicator.count),
                  !profile.indicator.contains(where: \.isWhitespace),
                  profile.home.hasPrefix("/") || profile.home.hasPrefix("~/") else {
                throw ConfigurationError.invalid("Each profile needs an ID, name, 1–2 character indicator, and absolute or ~/ home path.")
            }
        }
        return self
    }
}

enum ConfigurationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case let .invalid(message): message }
    }
}

struct ConfigurationFile {
    static let defaultURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".config/burnbar/config.json")
    let url: URL

    func load() throws -> BurnbarConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(BurnbarConfiguration.self, from: data).validated()
        } catch let error as ConfigurationError {
            throw error
        } catch {
            // Do not echo file contents: a user may accidentally paste credentials here.
            throw ConfigurationError.invalid("Invalid configuration. Check the JSON format and required profile fields.")
        }
    }

    func save(_ configuration: BurnbarConfiguration) throws {
        let validated = try configuration.validated()
        let data = try formattedData(validated)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func formattedData(_ configuration: BurnbarConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        func scalar<Value: Encodable>(_ value: Value) throws -> String {
            String(decoding: try encoder.encode(value), as: UTF8.self)
        }

        let profiles = try configuration.profiles.map { profile in
            var fields = [
                "\"provider\": \(try scalar(profile.provider))",
                "\"name\": \(try scalar(profile.name))",
                "\"indicator\": \(try scalar(profile.indicator))",
                "\"home\": \(try scalar(profile.home))"
            ]
            if let color = profile.color { fields.append("\"color\": \(try scalar(color))") }
            fields.append("\"enabled\": \(try scalar(profile.enabled))")
            fields.append("\"id\": \(try scalar(profile.id))")
            return "    {\n      " + fields.joined(separator: ",\n      ") + "\n    }"
        }
        let array = profiles.isEmpty ? "[]" : "[\n" + profiles.joined(separator: ",\n") + "\n  ]"
        let json = "{\n  \"refreshIntervalMinutes\": \(try scalar(configuration.refreshIntervalMinutes)),\n  \"profiles\": \(array)\n}\n"
        return Data(json.utf8)
    }
}
