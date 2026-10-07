import Foundation
import Testing
@testable import Burnbar

struct ProfileConfigurationFormatTests {
    @Test
    func savesFieldsInHumanOrientedOrder() throws {
        var profile = makeProfile()
        profile.color = "#AB12EF"
        let config = BurnbarConfiguration(refreshIntervalMinutes: 30, profiles: [profile])
        try withFile { file in
            try file.save(config)
            let text = try String(contentsOf: file.url, encoding: .utf8)
            #expect(text == """
            {
              "refreshIntervalMinutes": 30,
              "profiles": [
                {
                  "provider": "codex",
                  "name": "Test",
                  "indicator": "T",
                  "home": "~/.codex",
                  "color": "#AB12EF",
                  "enabled": true,
                  "id": "test"
                }
              ]
            }

            """)
            #expect(try file.load() == config)
            try file.save(config)
            #expect(try String(contentsOf: file.url, encoding: .utf8) == text)
        }
    }

    @Test
    func escapesStringsAndOmitsAbsentOptions() throws {
        var profile = makeProfile()
        profile.name = "Quoted \"name\"\nSecond line\\path"
        profile.home = "/tmp/a\"b\nc\\d"
        let config = BurnbarConfiguration(profiles: [profile])
        try withFile { file in
            try file.save(config)
            let data = try Data(contentsOf: file.url)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let profiles = try #require(object["profiles"] as? [[String: Any]])
            #expect(profiles[0]["name"] as? String == profile.name)
            #expect(profiles[0]["home"] as? String == profile.home)
            #expect(profiles[0]["color"] == nil)
            #expect(profiles[0]["refreshIntervalMinutes"] == nil)
            #expect(try file.load() == config)
        }
    }

    @Test
    func savesEmptyProfilesAsJSONArray() throws {
        try withFile { file in
            try file.save(.defaults)
            #expect(try file.load() == .defaults)
            #expect(try String(contentsOf: file.url, encoding: .utf8).contains("\"profiles\": []"))
        }
    }

    private func makeProfile() -> BurnbarConfiguration.Profile {
        .init(id: "test", provider: .codex, name: "Test", indicator: "T", home: "~/.codex", enabled: true)
    }

    private func withFile(_ body: (ConfigurationFile) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(ConfigurationFile(url: directory.appendingPathComponent("config.json")))
    }
}
