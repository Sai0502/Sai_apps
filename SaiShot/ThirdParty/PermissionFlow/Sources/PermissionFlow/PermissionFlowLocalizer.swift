#if os(macOS)
import Foundation

@available(macOS 13.0, *)
enum PermissionFlowLocalizer {
    /// Resolves a localized string from the best matching `.lproj` bundle for
    /// the injected locale. This keeps all custom locale selection in one
    /// place, while still letting the rest of the UI use plain localization
    /// keys and format strings.
    static func string(
        _ key: String,
        defaultValue: String,
        localeIdentifier: String?
    ) -> String {
        localizedBundle(for: localeIdentifier)?
            .localizedString(forKey: key, value: defaultValue, table: nil)
            ?? resourcesBundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }

    /// Resolves the packaged resource bundle without relying on SwiftPM's
    /// generated `Bundle.module` accessor, which only looks beside the
    /// executable's bundle root and then falls back to a build-machine path
    /// baked in at compile time. In a hand-assembled .app the resources live in
    /// Contents/Resources, so both of those can miss and `Bundle.module` traps
    /// with "could not load resource bundle". Searching the app's own bundle
    /// first keeps the permission panel alive regardless of where the build put
    /// the bundle or what the project folder is called now.
    static let resourcesBundle: Bundle = {
        let bundleName = "SaiShot_PermissionFlow.bundle"
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle(for: PermissionFlowController.self).resourceURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(),
        ]
        for candidate in candidates.compactMap({ $0 }) {
            let url = candidate.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return Bundle.module
    }()

    private static func localizedBundle(for localeIdentifier: String?) -> Bundle? {
        guard let localeIdentifier, localeIdentifier.isEmpty == false else {
            return nil
        }

        let preferences = localizationPreferences(for: localeIdentifier)
        guard let localization = Bundle.preferredLocalizations(
            from: resourcesBundle.localizations,
            forPreferences: preferences
        ).first,
        let path = resourcesBundle.path(forResource: localization, ofType: "lproj") else {
            return nil
        }

        return Bundle(path: path)
    }

    private static func localizationPreferences(for localeIdentifier: String) -> [String] {
        let normalizedIdentifier = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        let locale = Locale(identifier: normalizedIdentifier)

        var preferences = [normalizedIdentifier]
        if let identifier = locale.language.languageCode?.identifier {
            if let script = locale.language.script?.identifier {
                preferences.append("\(identifier)-\(script)")
            }
            preferences.append(identifier)
        }

        return Array(NSOrderedSet(array: preferences)) as? [String] ?? preferences
    }
}
#endif
