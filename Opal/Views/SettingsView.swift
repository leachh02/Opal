//
//  SettingsView.swift
//  Opal
//
//  The editor, where new notes go, downloaded files, the connection, and
//  the app's version.
//

import SwiftUI

struct SettingsView: View {
    let vault: Vault

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var index: NoteIndex
    @Environment(\.dismiss) private var dismiss

    @AppStorage(EditorPreferences.startModeKey) private var startMode = MarkdownEditorController.Mode.live
    @AppStorage(EditorPreferences.textScaleKey) private var textScale = 100
    @AppStorage(EditorPreferences.autocorrectKey) private var autocorrect = true
    @AppStorage(EditorPreferences.spellCheckKey) private var spellCheck = true

    @State private var vaultSettings: VaultSettings
    @AppStorage(StoragePreferences.clearDownloadsOnLaunchKey) private var clearDownloadsOnLaunch = true

    @State private var isPickingFolder = false
    @State private var cacheSize: Int64?

    init(vault: Vault) {
        self.vault = vault
        _vaultSettings = State(initialValue: VaultSettings.load(for: vault))
    }

    var body: some View {
        NavigationStack {
            Form {
                editorSection
                newNotesSection
                storageSection
                connectionSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: vaultSettings) { vaultSettings.save(for: vault) }
        .sheet(isPresented: $isPickingFolder) {
            FolderPickerView(title: "New Notes Folder", vaultRoot: vault.root) { folder in
                vaultSettings.newNoteFolder = index.relativePath(folder)
                isPickingFolder = false
            }
            .environmentObject(index)
        }
        .task { cacheSize = await FileCache.totalSize() }
    }

    // MARK: Sections

    private var editorSection: some View {
        Section("Editor") {
            Picker("Open Notes In", selection: $startMode) {
                Text("Live Preview").tag(MarkdownEditorController.Mode.live)
                Text("Source").tag(MarkdownEditorController.Mode.source)
            }
            Stepper(value: $textScale, in: EditorPreferences.textScales, step: 10) {
                LabeledContent("Text Size", value: "\(textScale)%")
            }
            Toggle("Autocorrect", isOn: $autocorrect)
            Toggle("Check Spelling", isOn: $spellCheck)
        }
    }

    private var newNotesSection: some View {
        Section {
            Picker("Location", selection: $vaultSettings.newNoteLocation) {
                Text("Top of Vault").tag(NewNoteLocation.vaultRoot)
                Text("Same Folder as Note").tag(NewNoteLocation.currentFolder)
                Text("Chosen Folder").tag(NewNoteLocation.folder)
            }
            if vaultSettings.newNoteLocation == .folder {
                Button {
                    isPickingFolder = true
                } label: {
                    LabeledContent("Folder", value: vaultSettings.newNoteFolder.isEmpty ? "Top of Vault" : vaultSettings.newNoteFolder)
                }
                .tint(.primary)
            }
        } header: {
            Text("New Notes")
        } footer: {
            Text("Where a note is saved when you tap a link to a note that doesn't exist yet. Notes made with + go in the folder you're in. This is set for each vault.")
        }
    }

    private var storageSection: some View {
        Section {
            Toggle("Clear When Opal Opens", isOn: $clearDownloadsOnLaunch)
            LabeledContent("Downloaded Files") {
                if let cacheSize {
                    Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                } else {
                    ProgressView()
                }
            }
            Button("Clear Downloaded Files", role: .destructive) {
                FileCache.clearAll()
                cacheSize = 0
            }
            .disabled(cacheSize == 0)
        } header: {
            Text("Storage")
        } footer: {
            Text(clearDownloadsOnLaunch
                 ? "Copies of images and other files Opal has shown are kept while it's open, then deleted the next time it opens. Nothing on your server changes."
                 : "Copies of images and other files Opal has shown are kept so they open quickly next time, until you clear them. Nothing on your server changes.")
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            if let settings = appState.settings {
                LabeledContent("Server", value: settings.title)
                if settings.displayName?.isEmpty == false {
                    LabeledContent("Address", value: settings.port.map { "\(settings.host):\($0)" } ?? settings.host)
                }
                LabeledContent("Share", value: settings.share)
                LabeledContent("User", value: settings.isGuest ? "Guest" : settings.username)
            }
            LabeledContent("Vault", value: vaultName)
            Button("Switch Vault", systemImage: "folder.badge.gearshape") {
                dismiss()
                appState.closeVault()
            }
            Button("Disconnect", systemImage: "eject", role: .destructive) {
                dismiss()
                Task { await appState.disconnect() }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: version)
            Link(destination: URL(string: "https://github.com/leachh02/Opal")!) {
                Label("Opal on GitHub", systemImage: "arrow.up.right.square")
            }
        }
    }

    // MARK: Values

    private var vaultName: String {
        let name = VaultPath.name(of: vault.root)
        return name.isEmpty ? appState.settings?.share ?? "Vault" : name
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
