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

- A Mac with Xcode 16.4 or later
- An iPhone on iOS 18.5 or later
- An Obsidian vault in a folder shared over SMB (a NAS, a Mac with File Sharing on, or a Windows or Linux computer), on the same network as your iPhone
- An Apple Account. A free one works. A paid Apple Developer membership keeps the app installed longer.
- Node.js, only if you change the editor

Opal isn't on the App Store yet, so you build it yourself with Xcode.

### Install on your iPhone

1. Clone the project and open it in Xcode:

   ```bash
   git clone https://github.com/leachh02/Opal.git
   cd Opal
   open Opal.xcodeproj
   ```

   Xcode downloads the Swift packages Opal uses the first time it opens.

2. Set up signing:
   - In Xcode, select the **Opal** project, then the **Opal** target, then **Signing & Capabilities**.
   - Choose your own Apple Account under **Team**. If it isn't listed, add it in **Xcode > Settings > Accounts**.
   - Change the **Bundle Identifier** to something unique to you, such as `com.yourname.Opal`.

3. Connect your iPhone with a cable and choose it at the top of the Xcode window. The first time, turn on **Developer Mode** on the iPhone in **Settings > Privacy & Security** and restart it when asked.

4. Press **Run** (⌘R). The first time, the iPhone may say the developer isn't trusted. Trust it in **Settings > General > VPN & Device Management**, then open Opal.

With a free Apple Account, the app stops opening after 7 days. Run it from Xcode again to renew it. With a paid membership it lasts a year.

You can also run Opal in the iOS Simulator: choose a simulator instead of your iPhone in step 3.

### Connect to your vault

1. Tap **Connect to Server** and enter:
   - **Host:** the server's IP address or name, such as `192.168.1.5` or `my-nas.local`. Servers Opal finds on your network are listed below the form, so you can tap one.
   - **Share:** the name of the shared folder, not a full path.
   - **Port:** leave this empty unless your server uses a port other than 445.
   - Your username and password, or **Guest** if the share allows it.
2. Allow Opal to use your local network when iOS asks. Without it, Opal can't reach the server.
3. Find your vault in the share and tap **Open**. A vault is the folder that contains the `.obsidian` folder.

Opal remembers the server and vault and reconnects next time. Passwords are kept in the iPhone's Keychain.

#### Sharing a vault from a Mac

1. On the Mac, open **System Settings > General > Sharing**.
2. Turn on **File Sharing**, then click the ⓘ button next to it.
3. Add the folder that holds your vault under **Shared Folders**.

In Opal, use the Mac's name (shown at the top of the Sharing settings, such as `my-mac.local`) or its IP address as the host. Use the folder's name as the share, and sign in with your Mac username and password.

### Working on the editor

The editor lives in `EditorWeb/` and is bundled into `Opal/Resources/Editor/`. The built files are committed, so you only need this after changing the editor:

```bash
cd EditorWeb
npm install
npm run build
```

Debug builds launched with the `-OpalEditorDemo` argument open the editor with sample text, no SMB server needed.

### Running the tests

The app's tests run in Xcode with **Product > Test** (⌘U). The editor's tests run in `EditorWeb/` with `npm test`.

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

MIT © Harrison Leach. See [LICENSE](LICENSE).

---

Opal was built with love and local-first privacy in mind. Enjoy writing!
