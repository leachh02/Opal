//
//  AppState.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//

import Foundation
import SMBClient
import Combine

class AppState: ObservableObject {
    @Published var treeAccessor: TreeAccessor? = nil {
        didSet {
            persistTreeAccessor()
        }
    }

    @Published var currentVaultPath: String = "" {
        didSet {
            UserDefaults.standard.set(currentVaultPath, forKey: "vaultPath")
        }
    }

    init() {
        self.currentVaultPath = UserDefaults.standard.string(forKey: "vaultPath") ?? ""
        // Optional: Restore TreeAccessor from previous login logic if securely stored
    }

    private func persistTreeAccessor() {
        // You could persist basic info like host/username/password if needed
        // For now, we assume user will reconnect on app launch
    }
}
