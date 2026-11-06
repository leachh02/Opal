# Opal – Obsidian Vault Browser & Editor for iOS 📁📝

**Opal** is a SwiftUI-based iOS app that lets you connect to an SMB server and browse your Obsidian vaults. With a simple, lightweight live-preview Markdown editor, it's the perfect way to work with your notes stored on your home network — no cloud required.

---

## ✨ Features

- 📡 Connect to an SMB file server
- 📂 Browse folders and files like the iOS Notes app
- 🖋️ Edit Markdown files with a live preview editor built on CodeMirror
- 🔐 Local-first, privacy-respecting
- 💡 Supports nested vaults and custom share paths

---

## 🚀 Getting Started

### Requirements

- Xcode 16+
- iOS 18.5+
- Access to an SMB share with an Obsidian vault
- Node.js (only needed if you change the editor)

### Clone & Run

```bash
git clone https://github.com/leachh02/opal.git
cd opal
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

## 🧱 Built With

- [SMBClient](https://github.com/kishikawakatsumi/SMBClient) – Swift-native SMB library
- [CodeMirror 6](https://codemirror.net) – the Markdown editor, running in a web view
- SwiftUI + Combine

---

## 💸 App Store Distribution

Unfortunately, I discovered that publishing an app on the App Store requires an Apple developer account enrolled in the Apple Developer Program, which costs $150 AUD/year... Sadly, I can't justify the funds for this at the moment, especially considering this is a passion project. However, if this project garners enough traction and there is demand for it, I would be keen to get it out to the public!

---

## 💸 Sponsorship / Support

I built Opal to scratch my own itch — but if you've found it useful and want to help cover publishing costs (e.g. the $150 AUD/year Apple Developer fee), feel free to:

- ⭐ Star this repo to show support
- ☕ Buy me a coffee
- 💌 Sponsor me on GitHub

---

## 📢 Roadmap

- Multiple vault support
- Image support and local preview
- iPad layout

---

## 📄 License

MIT © Harrison Leach

---

Opal was built with love and local-first privacy in mind. Enjoy writing offline. ✍️
