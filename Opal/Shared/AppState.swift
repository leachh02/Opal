//
//  AppState.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import Foundation
import SMBClient
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var treeAccessor: TreeAccessor? = nil {
        didSet {
            persistTreeAccessor()
        }
    }
    
    @Published var displayName: String? {
        didSet {
            UserDefaults.standard.set(displayName, forKey: "displayName")
        }
    }
    
    @Published var host: String {
        didSet {
            UserDefaults.standard.set(host, forKey: "host")
        }
    }

    @Published var port: String? {
        didSet {
            UserDefaults.standard.set(port, forKey: "port")
        }
    }

    @Published var share: String {
        didSet {
            UserDefaults.standard.set(share, forKey: "share")
        }
    }

    @Published var username: String = ""
    @Published var password: String = ""

    @Published var currentVaultPath: String = "" {
        didSet {
            UserDefaults.standard.set(currentVaultPath, forKey: "currentVaultPath")
        }
    }
    
    @Published var isLoggedIn: Bool = false
    @Published var vaultSelected: Bool = false
    
    let smbService = SMBConnectionService()

    init() {
        self.displayName = UserDefaults.standard.string(forKey: "displayName")
        self.host = UserDefaults.standard.string(forKey: "host") ?? ""
        self.port = UserDefaults.standard.string(forKey: "port")
        self.share = UserDefaults.standard.string(forKey: "share") ?? ""
        self.currentVaultPath = UserDefaults.standard.string(forKey: "currentVaultPath") ?? ""
        loadSavedCredentialIfExists()
    }

    private func persistTreeAccessor() {
        // You could persist basic info like host/username/password if needed
        // For now, we assume user will reconnect on app launch
    }
    
    func connect(isRegistered: Bool, saveCredentials: Bool = true) async {
        await smbService.connect(
            host: host,
            port: port,
            share: share,
            username: isRegistered ? username : "",
            password: isRegistered ? password : "",
            saveCredentials: saveCredentials
        )

        self.isLoggedIn = smbService.isConnected
        self.treeAccessor = smbService.treeAccessor
    }
    
    func loadSavedCredentialIfExists() {
        guard !host.isEmpty, !share.isEmpty else { return }

        if let credential = smbService.loadStoredCredential(for: host, share: share) {
            self.username = credential.username
            self.password = credential.password
        }
    }
    
    func logout() {
        self.isLoggedIn = false
        self.vaultSelected = false
    }
    
    func attemptAutoLogin() async {
        // Check UserDefaults for stored host/share
        if let savedHost = UserDefaults.standard.string(forKey: "host"),
           let savedShare = UserDefaults.standard.string(forKey: "share") {
            self.host = savedHost
            self.share = savedShare
            loadSavedCredentialIfExists()
            await connect(isRegistered: !self.username.isEmpty, saveCredentials: false)
        }
        if !self.currentVaultPath.isEmpty{
            self.vaultSelected = true
        }
    }
    
}
