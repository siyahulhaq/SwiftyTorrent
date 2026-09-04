//
//  ICloudEditSheet.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 01/09/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

public struct ICloudEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    public let account: CloudAccount
    public var onSaved: (() -> Void)?
    
    @State private var displayName: String
    @State private var currentPath: String
    @State private var newBookmarkBase64: String?
    @State private var showDocumentPicker = false
    @State private var errorMessage: String?
    
    public init(account: CloudAccount, onSaved: (() -> Void)? = nil) {
        self.account = account
        self.onSaved = onSaved
        _displayName = State(initialValue: account.displayName)
        _currentPath = State(initialValue: account.customProperties["path"] ?? "iCloud Drive")
    }
    
    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Folder Details")) {
                    HStack {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        TextField("Display Name", text: $displayName)
                    }
                    
                    HStack(alignment: .top) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Linked Path")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(currentPath)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Button(action: {
                        showDocumentPicker = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Change Linked Folder")
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button(action: saveChanges) {
                        HStack {
                            Spacer()
                            Text("Save Changes")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Edit iCloud Folder")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPickerPresenter(contentTypes: [.folder]) { pickedURL in
                    updateFolder(with: pickedURL)
                }
            }
        }
    }
    
    private func updateFolder(with url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            self.errorMessage = "Failed to access security-scoped iCloud folder."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let base64 = bookmarkData.base64EncodedString()
            let folderName = url.lastPathComponent.isEmpty ? "iCloud Drive" : url.lastPathComponent
            
            self.newBookmarkBase64 = base64
            self.currentPath = url.path
            if self.displayName.isEmpty || self.displayName == account.displayName {
                self.displayName = folderName
            }
        } catch {
            self.errorMessage = "Could not generate bookmark for folder: \(error.localizedDescription)"
        }
    }
    
    private func saveChanges() {
        var updatedProps = account.customProperties
        if let newB64 = newBookmarkBase64 {
            updatedProps["bookmark"] = newB64
            updatedProps["path"] = currentPath
        }
        
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedAccount = CloudAccount(
            id: account.id,
            providerId: account.providerId,
            accountName: trimmedName,
            displayName: trimmedName,
            accessToken: account.accessToken,
            refreshToken: account.refreshToken,
            tokenExpiryDate: account.tokenExpiryDate,
            customProperties: updatedProps,
            quotaTotal: account.quotaTotal,
            quotaUsed: account.quotaUsed,
            createdAt: account.createdAt
        )
        
        CloudAccountManager.shared.save(account: updatedAccount)
        onSaved?()
        dismiss()
    }
}
