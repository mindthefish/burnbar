import Foundation
import Testing
@testable import Burnbar

struct ProfileColorTests {
    @Test
    func legacyProfileJSONDecodesWithoutColor() throws {
        let json = #"{"id":"private","provider":"codex","name":"Private","indicator":"P","home":"~/.codex","enabled":true}"#
        let profile = try JSONDecoder().decode(BurnbarConfiguration.Profile.self, from: Data(json.utf8))
        #expect(profile.color == nil)
        #expect(profile.accent == .privateOpenAI)
    }

    @Test
    func colorRoundTripsAndProvidesCustomAccent() throws {
        var profile = makeProfile()
        profile.color = "#aB12Ef"
        let config = try BurnbarConfiguration(profiles: [profile]).validated()
        let decoded = try JSONDecoder().decode(BurnbarConfiguration.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
        #expect(profile.accent == .custom(hex: "#aB12Ef"))
        #expect(profile.emptySnapshot.accent == profile.accent)
    }

    @Test
    func rejectsMalformedColorsWithGenericMessage() {
        for color in ["", "aB12Ef", "#123", "#1234567", "#GG12EF", " #AB12EF", "#AB12EF\n"] {
            var profile = makeProfile()
            profile.color = color
            do {
                _ = try BurnbarConfiguration(profiles: [profile]).validated()
                Issue.record("Malformed profile color was accepted.")
            } catch let error as ConfigurationError {
                #expect(error.errorDescription == "Profile color must use the hex format #RRGGBB.")
            } catch {
                Issue.record("Unexpected configuration error type.")
            }
        }
    }

    @Test
    func missingColorPreservesProviderFallbacks() {
        #expect(makeProfile().accent == .privateOpenAI)
        #expect(makeProfile(id: "work").accent == .workOpenAI)
        #expect(makeProfile(provider: .claude).accent == .claude)
    }

    @Test
    func defaultsHaveNoProfiles() throws {
        #expect(BurnbarConfiguration.defaults.profiles.isEmpty)
        #expect(try BurnbarConfiguration.defaults.validated() == .defaults)
    }

    private func makeProfile(
        id: String = "private",
        provider: BurnbarConfiguration.Profile.Provider = .codex
    ) -> BurnbarConfiguration.Profile {
        .init(id: id, provider: provider, name: "Test", indicator: "T", home: "~/.codex", enabled: true)
    }
}
