import Foundation

/// Identity of the running bundle. Shared by user-visible branding and
/// process-name lookups so a renamed build stays consistent everywhere.
enum AppIdentity {
    static let displayName: String = {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "SaiShot"
    }()

    static let executableName: String = {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)
            ?? ProcessInfo.processInfo.processName
    }()
}

/// Resolves UI strings from the per-language `.lproj` bundles shipped inside
/// the app bundle's `Contents/Resources/`.
///
/// The app has an in-app language picker, so we can't lean on
/// `NSLocalizedString` — that keys off the *system* locale. Instead we load the
/// `.lproj` bundle for the user's chosen `AppLanguage` explicitly and look keys
/// up there, which also lets language changes take effect live.
enum Localizer {
    /// Sentinel returned by `localizedString` when a key is absent — distinct
    /// from any real value so we can detect misses and fall back.
    private static let missing = "\u{0}SaiShot.l10n.missing\u{0}"

    /// (language, resolved bundle) — recomputed only when the language changes.
    private static var cache: (lang: AppLanguage, bundle: Bundle)?

    private static func bundle(for lang: AppLanguage) -> Bundle {
        if let cache, cache.lang == lang { return cache.bundle }
        let resolved: Bundle
        if let path = Bundle.main.path(forResource: lang.lprojName, ofType: "lproj"),
           let lproj = Bundle(path: path) {
            resolved = lproj
        } else if let sourceLproj = sourceTreeBundle(for: lang) {
            resolved = sourceLproj
        } else {
            // Running unbundled (e.g. `swift run`) — no .lproj on disk.
            resolved = .main
        }
        cache = (lang, resolved)
        return resolved
    }

    private static func sourceTreeBundle(for lang: AppLanguage) -> Bundle? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(lang.lprojName).lproj")
        return Bundle(url: url)
    }

    /// The localized string for `key` in the current language. Falls back to
    /// English, then to the raw key, so a missing entry is visible rather than
    /// crashing or blanking the UI.
    static func string(_ key: String) -> String {
        let lang = Defaults.language
        let value = bundle(for: lang).localizedString(forKey: key, value: missing, table: nil)
        if value != missing { return branded(value) }
        if lang != .en {
            let english = bundle(for: .en).localizedString(forKey: key, value: missing, table: nil)
            if english != missing { return branded(english) }
        }
        return key
    }

    private static func branded(_ value: String) -> String {
        let appDisplayName = AppIdentity.displayName
        guard appDisplayName != "SaiShot", value.contains("SaiShot") else { return value }
        // Protect an already-branded name before replacing the bare brand so a
        // value containing the display name cannot become double-branded.
        let placeholder = "\u{0}APP_NAME\u{0}"
        return value
            .replacingOccurrences(of: appDisplayName, with: placeholder)
            .replacingOccurrences(of: "SaiShot", with: appDisplayName)
            .replacingOccurrences(of: placeholder, with: appDisplayName)
    }
}
