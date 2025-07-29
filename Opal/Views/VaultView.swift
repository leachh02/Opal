////
////  VaultView.swift
////  Opal
////
////  Created by Harrison Leach on 29/7/2025.
////
//
//
//import SwiftUI
//
//struct VaultView: View {
//    @ObservedObject var service: VaultService
//    let basePath: String
//
//    @State private var items: [VaultItem] = []
//    @State private var error: String?
//    @State private var isLoading = true
//    @State private var navigationPath = NavigationPath()
//
//    var body: some View {
//        NavigationStack(path: $navigationPath) {
//            Group {
//                if isLoading {
//                    ProgressView("Loading vault...")
//                } else if let error {
//                    Text("Error: \(error)")
//                        .foregroundColor(.red)
//                } else {
//                    List(items) { item in
//                        switch item {
//                        case .folder(let name, let path):
//                            NavigationLink(value: item) {
//                                HStack {
//                                    Image(systemName: "folder")
//                                    Text(name)
//                                }
//                            }
//
//                        case .file(let name, let path):
//                            NavigationLink(destination: EditorView(filePath: path, fileName: name, service: service)) {
//                                HStack {
//                                    Image(systemName: "doc.plaintext")
//                                    Text(name)
//                                }
//                            }
//                        }
//                    }
//                }
//            }
//            .navigationTitle(vaultName)
//            .navigationDestination(for: VaultItem.self) { item in
//                VaultSubfolderView(service: service, item: item)
//            }
//            .onAppear {
//                Task {
//                    await loadDirectory(basePath)
//                }
//            }
//        }
//    }
//
//    private func loadDirectory(_ path: String) async {
//        do {
//            items = try await service.listAllDirectoryItems(path: path)
//            isLoading = false
//        } catch {
//            self.error = error.localizedDescription
//            isLoading = false
//        }
//    }
//
//    private var vaultName: String {
//        basePath.components(separatedBy: "/").last ?? "Vault"
//    }
//}
