# Opal – Obsidian Vault Browser & Editor for iOS

**Opal** is a SwiftUI-based iOS app that lets you connect to an SMB server and browse your Obsidian vaults. With a simple, lightweight live-preview Markdown editor, it's the perfect way to work with your notes stored on your home network (no cloud required).

---

## Features

- Connect to an SMB file server
- Browse folders and files like the iOS Notes app
- Edit Markdown files with a live preview editor built on CodeMirror
- Local-first, privacy-respecting
- Supports nested vaults and custom share paths

---

## Getting Started

### Requirements

- Xcode 16+
- iOS 18.5+
- Access to an SMB share with an Obsidian vault
- Node.js (only needed if you change the editor)

### Clone & Run

```bash
git clone https://github.com/leachh02/Opal.git
cd Opal
open Opal.xcodeproj
```

Then build and run it in the iOS Simulator or on a real device.

### Working on the editor

The editor lives in `EditorWeb/` and is bundled into `Opal/Resources/Editor/`. The built files are committed, so you only need this after changing the editor:

```bash
cd EditorWeb
npm install
npm run build
```

Debug builds launched with the `-OpalEditorDemo` argument open the editor with sample text, no SMB server needed.

---

## Built With

- [SMBClient](https://github.com/kishikawakatsumi/SMBClient) – Swift-native SMB library
- [CodeMirror 6](https://codemirror.net) – the Markdown editor, running in a web view
- SwiftUI + Combine

---

## Sponsorship / Support

I built Opal to scratch my own itch, but if you've found it useful and want to help cover publishing costs (e.g. the $150 AUD/year Apple Developer fee), feel free to:

- Star this repo to show support
- [Buy me a coffee](https://buymeacoffee.com/leachh02)
- [Sponsor me on GitHub](https://github.com/sponsors/leachh02)

---

## Roadmap

- [ ] Multiple vault support
- [ ] iPad layout

---

## License

MIT © Harrison Leach

---

Opal was built with love and local-first privacy in mind. Enjoy writing!
