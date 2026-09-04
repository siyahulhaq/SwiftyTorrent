//
//  GoogleDriveAuthSheet.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct GoogleDriveAuthSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    
    // OAuth configuration
    @State private var clientId: String = UserDefaults.standard.string(forKey: "google_drive_client_id") ?? ""
    @State private var clientSecret: String = UserDefaults.standard.string(forKey: "google_drive_client_secret") ?? ""
    
    // Direct Access Token
    @State private var directAccessToken: String = ""
    
    // State
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCopiedAlert = false
    
    public var onAccountConnected: (() -> Void)?
    
    public init(onAccountConnected: (() -> Void)? = nil) {
        self.onAccountConnected = onAccountConnected
    }
    
    public var body: some View {
        NavigationView {
            Form {
                // MARK: - Method Picker
                Section {
                    Picker("Method", selection: $selectedTab) {
                        Text("OAuth 2.0").tag(0)
                        Text("Direct Token").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                if selectedTab == 0 {
                    // MARK: - OAuth Section
                    Section(header: Text("Google Drive Credentials"), footer: Text("Enter your OAuth 2.0 Client ID created in Google Cloud Console. Leave Client Secret empty unless configured as Web Application.")) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.key")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            TextField("Client ID (e.g. 123...apps.googleusercontent.com)", text: $clientId)
                                .disableAutocapitalizationIfAvailable()
                                .font(.system(size: 14))
                        }
                        
                        HStack {
                            Image(systemName: "lock")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            SecureField("Client Secret (Optional)", text: $clientSecret)
                                .disableAutocapitalizationIfAvailable()
                                .font(.system(size: 14))
                        }
                    }
                    
                    Section {
                        Button(action: startOAuthSignIn) {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Text("Sign in with Google")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }
                    
                    // MARK: - Setup Instructions
                    Section(header: Text("How to get a free Google Client ID")) {
                        #if !os(tvOS)
                        DisclosureGroup("Step-by-step setup guide") {
                            instructionStepsView
                        }
                        #else
                        instructionStepsView
                        #endif
                    }
                } else {
                    // MARK: - Direct Token Section
                    Section(header: Text("Direct Access Token"), footer: Text("Paste a Google OAuth access token or bearer token for direct access.")) {
                        #if !os(tvOS)
                        TextEditor(text: $directAccessToken)
                            .frame(minHeight: 100)
                            .font(.system(size: 13, design: .monospaced))
                        #else
                        TextField("Access Token", text: $directAccessToken)
                        #endif
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
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
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
    
    private var instructionStepsView: some View {
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
            
            #if !os(tvOS)
            Button(action: copyBundleId) {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Bundle Identifier (com.siyahul.SwiftyTorrent)")
                        .font(.caption)
                }
            }
            .padding(.top, 4)
            #endif
        }
        .padding(.vertical, 6)
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
        #if canImport(UIKit) && !os(tvOS)
        UIPasteboard.general.string = "com.siyahul.SwiftyTorrent"
        showCopiedAlert = true
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("com.siyahul.SwiftyTorrent", forType: .string)
        showCopiedAlert = true
        #endif
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
                #if os(tvOS)
                let rootVC: PlatformViewController? = nil
                #elseif canImport(UIKit)
                let rootVC: PlatformViewController? = await UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first(where: { $0.isKeyWindow })?.rootViewController
                #elseif canImport(AppKit)
                let rootVC: PlatformViewController? = await NSApplication.shared.keyWindow?.contentViewController
                #endif
                
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
