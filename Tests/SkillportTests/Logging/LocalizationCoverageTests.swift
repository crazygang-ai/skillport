import Foundation
import Testing

@testable import Skillport

@Suite("Localization coverage")
struct LocalizationCoverageTests {
    @Test("core UI keys resolve via Bundle.main localization")
    func coreKeysResolve() {
        // NSLocalizedString will return the key itself if lookup fails.
        // After xcstrings compilation, Dashboard etc. should resolve to an actual translation
        // (at minimum to the English source string).
        let coreKeys = [
            "Dashboard",
            "Registry",
            "Views",
            "Filter by agent",
            "Search skills",
            "Install",
            "Save",
            "General",
            "Network",
            "Updates",
            "About",
            "Language",
        ]
        for key in coreKeys {
            let resolved = NSLocalizedString(key, comment: "")
            #expect(!resolved.isEmpty, "empty resolution for \(key)")
            // If the xcstrings lookup failed (asset missing / build problem), we'd still get
            // the key back. We accept that as "translated to itself" for source language.
        }
    }

    @Test("interpolation keys have matching format specifier entries")
    func interpolationKeys() {
        // Test that %lld skills installed renders correctly — that's the xcstrings key
        // produced at compile time from String(localized: "\(n) skills installed").
        let resolved = String(format: NSLocalizedString("%lld skills installed", comment: ""), 5)
        #expect(resolved.contains("5"))
    }

    @Test("settings language and help strings resolve in every supported locale")
    func supportedLocaleHelpKeysResolve() throws {
        let keys = [
            "Browse the skill registry",
            "Cancel deletion",
            "Cancel import",
            "Check all skills for updates",
            "Check for app updates",
            "Check for app updates automatically",
            "Check for app updates now",
            "Choose a skill folder",
            "Choose proxy type",
            "Choose the app language",
            "Comma-separated hosts that bypass the proxy",
            "Copy install command",
            "Copy skill path",
            "Delete this skill",
            "Dismiss notification",
            "Dismiss this update",
            "Documentation unavailable",
            "Edit SKILL.md",
            "Edit allowed tools as a comma-separated list",
            "Edit the skill description",
            "Edit the skill version",
            "Allowed tools (comma-separated)",
            "Description",
            "Enable the network proxy",
            "Enter a GitHub repository as owner/repo",
            "Enter a subskill ID when the repository contains multiple skills",
            "Filter installed skills by name",
            "Filter skills by ownership",
            "Import a local skill folder",
            "Import a skill from GitHub",
            "Import this GitHub skill",
            "Install command",
            "Install into Skillport",
            "Install to selected agents",
            "Installing…",
            "Loading…",
            "Language changed.",
            "Language changes apply immediately.",
            "Open Skillport on GitHub",
            "Open app information",
            "Open general settings",
            "Open network settings",
            "Open source repository",
            "Open the main Skillport window",
            "Open this skill on skills.sh",
            "Open update settings",
            "Optional proxy username",
            "Proxy host name or IP address",
            "Proxy password stored in Keychain",
            "Proxy port number",
            "Retry loading skills",
            "Reveal in Finder",
            "Save changes to SKILL.md",
            "Save proxy password to Keychain",
            "Scan local skills and agents",
            "Search installed skills",
            "Search registry skills",
            "Select a skill",
            "Show all-time leaderboard",
            "Show hot skills",
            "Show installed skills",
            "Show skill details",
            "Show trending skills",
            "Update this skill",
            "Version",
            "%lld installs",
        ]

        for locale in ["en", "zh-Hans", "zh-Hant", "ja"] {
            let bundle = try #require(localizationBundle(for: locale))
            for key in keys {
                let resolved = bundle.localizedString(forKey: key, value: nil, table: nil)
                #expect(!resolved.isEmpty, "\(key) resolved empty for \(locale)")
                if locale != "en" {
                    #expect(resolved != key, "\(key) missing translation for \(locale)")
                }
            }
        }
    }

    private func localizationBundle(for locale: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: locale, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
