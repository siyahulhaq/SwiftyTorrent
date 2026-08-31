//
//  GoogleDriveAuthSheet.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI
import UIKit

public struct GoogleDriveAuthSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    
    // OAuth configuration
    @State private var clientId: String = UserDefaults.standard.string(forKey: "google_drive_client_id") ?? ""
    @State private var clientSecret: String = UserDefaults.standard.string(forKey: "google_drive_client_secret") ?? ""
    
    // Direct Access Token configuration
    @State private var directAccessToken: String = ""
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCopiedAlert = false
    
    public var onAccountConnected: (() -> Void)?
    
    public init(onAccountConnected: (() -> Void)? = nil) {
        self.onAccountConnected = onAccountConnected
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Method Picker
                Section {
                    Picker("Sign-in Method", selection: $selectedTab) {
                        Text("OAuth 2.0").tag(0)
                        Text("Access Token").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                if selectedTab == 0 {
                    // MARK: - OAuth Section
                    Section(header: Text("Google Cloud Client Configuration"), footer: Text("Google requires an OAuth 2.0 Client ID from Google Cloud Console. Enter your Client ID below to sign in.")) {
                        TextField("Google Client ID", text: $clientId)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 14, design: .monospaced))
                        
                        SecureField("Client Secret (Optional)", text: $clientSecret)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 14, design: .monospaced))
                    }
                    
                    Section {
                        Button(action: startOAuthSignIn) {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                Text("Sign in with Google")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }
                    
                    // MARK: - Setup Instructions
                    Section(header: Text("How to get a free Google Client ID")) {
                        DisclosureGroup("Step-by-step setup guide") {
                            VStack(alignment: .leading, spacing: 10) {
                                instructionStep(
                                    number: "1",
                                    text: "Visit Google Cloud Console",
                                    link: "https://console.cloud.google.com/apis/credentials"
                                )
                                instructionStep(
                                    number: "2",
                                    text: "Create a Project and enable 'Google Drive API' in APIs & Services."
                                )
                                instructionStep(
                                    number: "3",
                                    text: "Go to Credentials > Create Credentials > OAuth client ID."
                                )
                                instructionStep(
                                    number: "4",
                                    text: "Select 'iOS' (Bundle ID: com.siyahul.SwiftyTorrent) or 'Web application'."
                                )
                                instructionStep(
                                    number: "5",
                                    text: "Paste your Client ID above and tap Sign in with Google."
                                )
                                
                                Button(action: copyBundleId) {
                                    HStack {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy Bundle Identifier (com.siyahul.SwiftyTorrent)")
                                            .font(.caption)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                } else {
                    // MARK: - Direct Token Section
                    Section(header: Text("Direct Access Token"), footer: Text("Paste a Google OAuth access token or bearer token for direct access.")) {
                        TextEditor(text: $directAccessToken)
                            .frame(minHeight: 100)
                            .font(.system(size: 13, design: .monospaced))
                    }
                    
                    Section {
                        Button(action: startDirectTokenSignIn) {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Text("Connect with Token")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(directAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Google Drive Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Copied!", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Bundle ID 'com.siyahul.SwiftyTorrent' copied to clipboard.")
            }
        }
    }
    
    private func instructionStep(number: String, text: String, link: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number + ".")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                if let link = link, let url = URL(string: link) {
                    Link(link, destination: url)
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    private func copyBundleId() {
        UIPasteboard.general.string = "com.siyahul.SwiftyTorrent"
        showCopiedAlert = true
    }
    
    private func startOAuthSignIn() {
        let trimmedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientId.isEmpty else { return }
        
        UserDefaults.standard.set(trimmedClientId, forKey: "google_drive_client_id")
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSecret.isEmpty {
            UserDefaults.standard.set(trimmedSecret, forKey: "google_drive_client_secret")
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let provider = GoogleDriveStorageProvider()
                let rootVC = await UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first(where: { $0.isKeyWindow })?.rootViewController
                
                _ = try await provider.authenticate(
                    clientId: trimmedClientId,
                    clientSecret: trimmedSecret.isEmpty ? nil : trimmedSecret,
                    from: rootVC
                )
                
                await MainActor.run {
                    isLoading = false
                    onAccountConnected?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    if (error as NSError).code != 401 { // Ignore user cancel
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    private func startDirectTokenSignIn() {
        let trimmedToken = directAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let provider = GoogleDriveStorageProvider()
                _ = try await provider.authenticateWithToken(accessToken: trimmedToken)
                
                await MainActor.run {
                    isLoading = false
                    onAccountConnected?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    self.errorMessage = "Failed to authenticate: \(error.localizedDescription)"
                }
            }
        }
    }
}
