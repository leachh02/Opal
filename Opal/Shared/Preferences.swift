//
//  Preferences.swift
//  Opal
//
//  Settings chosen on the Settings screen. Editor settings apply to every
//  vault; where new notes go is set per vault, as in Obsidian.
//

import Foundation

/// UserDefaults keys for the editor settings, read with `@AppStorage`.
enum EditorPreferences {
    /// A `MarkdownEditorController.Mode`: how notes first open.
    static let startModeKey = "editorStartMode"
    /// Text size as a percentage of the iPhone's own text size.
    static let textScaleKey = "editorTextScale"
    static let autocorrectKey = "editorAutocorrect"
    static let spellCheckKey = "editorSpellCheck"

    static let textScales = 80...160
}

/// UserDefaults keys for downloaded files.
enum StoragePreferences {
    /// Whether downloaded images and files are deleted each time Opal opens.
    /// On by default; off keeps them until cleared in Settings.
    static let clearDownloadsOnLaunchKey = "clearDownloadsOnLaunch"

    static func clearsDownloadsOnLaunch(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: clearDownloadsOnLaunchKey) as? Bool ?? true
    }
}

/// Where a note made by tapping a `[[link]]` to nothing is saved.
enum NewNoteLocation: String, CaseIterable, Codable {
    case vaultRoot
    case currentFolder
    case folder
}

/// Settings that belong to one vault.
struct VaultSettings: Codable, Equatable {
    var newNoteLocation: NewNoteLocation = .vaultRoot
    /// The folder for `.folder`, relative to the vault.
    var newNoteFolder = ""

    static func load(for vault: Vault, from defaults: UserDefaults = .standard) -> VaultSettings {
        guard let data = defaults.data(forKey: key(for: vault)),
              let settings = try? JSONDecoder().decode(VaultSettings.self, from: data)
        else { return VaultSettings() }
        return settings
    }

    func save(for vault: Vault, to defaults: UserDefaults = .standard) {
        guard !vault.id.isEmpty, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key(for: vault))
    }

    private static func key(for vault: Vault) -> String { "vaultSettings." + vault.id }
}
