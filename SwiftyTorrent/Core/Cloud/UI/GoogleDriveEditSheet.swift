//
//  GoogleDriveEditSheet.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 01/09/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI

public struct GoogleDriveEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    public let account: CloudAccount
    public var onSaved: (() -> Void)?
    
    @State private var displayName: String
    @State private var isReauthenticating = false
    @State private var errorMessage: String?
    
    public init(account: CloudAccount, onSaved: (() -> Void)? = nil) {
        self.account = account
        self.onSaved = onSaved
        _displayName = State(initialValue: account.displayName)
    }
    
    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account Details")) {
                    HStack {
                        Image(systemName: "pencil")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        TextField("Display Name", text: $displayName)
                    }
                    
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Account Email")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(account.accountName.isEmpty ? "Google Account" : account.accountName)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected On")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(account.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                    }
                }
                
                Section(header: Text("Account Actions")) {
                    Button(action: reauthenticate) {
                        HStack {
                            if isReauthenticating {
                                ProgressView()
                                    .padding(.trailing, 6)
                                Text("Re-authenticating...")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Re-authenticate Google Account")
                            }
                        }
                        .foregroundColor(.blue)
                    }
                    .disabled(isReauthenticating)
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
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReauthenticating)
                }
            }
            .navigationTitle("Edit Google Drive")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func reauthenticate() {
        isReauthenticating = true
        errorMessage = nil
        
        let provider = GoogleDriveStorageProvider(account: account)
        Task {
            do {
                _ = try await provider.authenticate(from: nil)
                await MainActor.run {
                    self.isReauthenticating = false
                    self.onSaved?()
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.isReauthenticating = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func saveChanges() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedAccount = CloudAccount(
            id: account.id,
            providerId: account.providerId,
            accountName: account.accountName,
            displayName: trimmedName,
            accessToken: account.accessToken,
            refreshToken: account.refreshToken,
            tokenExpiryDate: account.tokenExpiryDate,
            customProperties: account.customProperties,
            quotaTotal: account.quotaTotal,
            quotaUsed: account.quotaUsed,
            createdAt: account.createdAt
        )
        
        CloudAccountManager.shared.save(account: updatedAccount)
        onSaved?()
        dismiss()
    }
}
