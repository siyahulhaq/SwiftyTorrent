//
//  SMBAuthSheet.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI

public struct SMBAuthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bonjourBrowser = SMBBonjourBrowser()
    
    @State private var host: String = ""
    @State private var port: String = "445"
    @State private var share: String = ""
    @State private var basePath: String = ""
    @State private var isGuest: Bool = false
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var domain: String = ""
    @State private var serverName: String = ""
    @State private var isShowPassword: Bool = false
    
    @State private var isTesting: Bool = false
    @State private var isConnecting: Bool = false
    @State private var isDiscoveringShares: Bool = false
    @State private var availableShares: [String] = []
    @State private var testSuccess: Bool? = nil
    @State private var errorMessage: String? = nil
    
    public let editingAccount: CloudAccount?
    public var onConnected: (() -> Void)?
    
    public init(editingAccount: CloudAccount? = nil, onConnected: (() -> Void)? = nil) {
        self.editingAccount = editingAccount
        self.onConnected = onConnected
        
        if let account = editingAccount {
            let props = account.customProperties
            _host = State(initialValue: props["host"] ?? "")
            _port = State(initialValue: props["port"] ?? "445")
            _share = State(initialValue: props["share"] ?? "")
            _basePath = State(initialValue: props["basePath"] ?? "")
            let guest = (props["isGuest"] == "true") || (props["username"] ?? "").isEmpty
            _isGuest = State(initialValue: guest)
            _username = State(initialValue: props["username"] ?? "")
            _password = State(initialValue: props["password"] ?? "")
            _domain = State(initialValue: props["domain"] ?? "")
            _serverName = State(initialValue: account.displayName)
        }
    }
    
    public var body: some View {
        NavigationView {
            Form {
                // MARK: - Discovered Local Servers
                if editingAccount == nil && !bonjourBrowser.discoveredServers.isEmpty {
                    Section(header: HStack {
                        Text("Nearby SMB Servers")
                        Spacer()
                        if bonjourBrowser.isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }, footer: Text("Tap a discovered server to auto-fill its address.")) {
                        ForEach(bonjourBrowser.discoveredServers) { server in
                            Button(action: {
                                selectDiscoveredServer(server)
                            }) {
                                HStack {
                                    Image(systemName: server.name.lowercased().contains("mac") ? "laptopcomputer" : "server.rack")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                        .frame(width: 28)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.primary)
                                        
                                        Text(server.ipAddress ?? server.hostName)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundColor(.accentColor)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                
                // MARK: - Server Details
                Section(header: Text("Server Information"), footer: Text("Enter the server's IP address (e.g. 192.168.0.19) or hostname. Share name is optional: leave it blank to browse all available shares on the server.")) {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.indigo)
                            .frame(width: 24)
                        TextField("Server IP or Host (e.g. 192.168.0.19)", text: $host)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                    }
                    
                    HStack {
                        Image(systemName: "number")
                            .foregroundColor(.secondary)
                            .frame(width: 24)
                        TextField("Port (Default: 445)", text: $port)
                            .keyboardType(.numberPad)
                    }
                    
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        TextField("Share Name (Optional: leave blank for all shares)", text: $share)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button(action: discoverShares) {
                            if isDiscoveringShares {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Text("Find Shares")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .cornerRadius(6)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDiscoveringShares)
                    }
                    
                    if !availableShares.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Available Shares on Server (Tap to select or keep 'All Shares'):")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Button(action: {
                                        self.share = ""
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: self.share.isEmpty ? "checkmark.circle.fill" : "server.rack")
                                            Text("All Shares")
                                        }
                                        .font(.system(size: 13, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(self.share.isEmpty ? Color.blue : Color(UIColor.secondarySystemBackground))
                                        .foregroundColor(self.share.isEmpty ? .white : .primary)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    ForEach(availableShares, id: \.self) { s in
                                        Button(action: {
                                            self.share = s
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: self.share.caseInsensitiveCompare(s) == .orderedSame ? "checkmark.circle.fill" : "folder.fill")
                                                Text(s)
                                            }
                                            .font(.system(size: 13, weight: .medium))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(self.share.caseInsensitiveCompare(s) == .orderedSame ? Color.blue : Color(UIColor.secondarySystemBackground))
                                            .foregroundColor(self.share.caseInsensitiveCompare(s) == .orderedSame ? .white : .primary)
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    
                    HStack {
                        Image(systemName: "tray.full")
                            .foregroundColor(.secondary)
                            .frame(width: 24)
                        TextField("Subfolder Path (Optional, e.g. /Movies)", text: $basePath)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }
                
                // MARK: - Authentication
                Section(header: Text("Authentication")) {
                    Toggle("Connect as Guest / Anonymous", isOn: $isGuest)
                    
                    if !isGuest {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            TextField("Username (macOS Account Name)", text: $username)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.yellow)
                                .frame(width: 24)
                            if isShowPassword {
                                TextField("Password", text: $password)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            } else {
                                SecureField("Password", text: $password)
                            }
                            
                            Button(action: { isShowPassword.toggle() }) {
                                Image(systemName: isShowPassword ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            TextField("Workgroup / Domain (Optional)", text: $domain)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                    }
                }
                
                // MARK: - Display Settings
                Section(header: Text("Display Name")) {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.indigo)
                            .frame(width: 24)
                        TextField("Server Nickname (e.g. MacBook Pro Share)", text: $serverName)
                    }
                }
                
                // MARK: - Action Buttons
                Section {
                    Button(action: testConnection) {
                        HStack {
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .padding(.trailing, 6)
                                Text("Testing Connection...")
                            } else if testSuccess == true {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Connection Successful")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "bolt.fill")
                                Text("Test Connection")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isFormInvalid || isTesting || isConnecting)
                    
                    Button(action: saveAndConnect) {
                        HStack {
                            Spacer()
                            if isConnecting {
                                ProgressView()
                                    .padding(.trailing, 6)
                                Text(editingAccount != nil ? "Saving..." : "Connecting...")
                            } else {
                                Text(editingAccount != nil ? "Save Changes" : "Connect Server")
                                    .fontWeight(.bold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isFormInvalid || isConnecting)
                }
                
                if let error = errorMessage {
                    Section(header: Text("Connection Diagnostics")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.red)
                                
                                Text(error)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // MARK: - Mac Setup Tips
                Section(header: Text("Mac File Sharing Guide")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("To share folders from a Mac:")
                            .font(.system(size: 13, weight: .semibold))
                        Text("1. On your Mac, go to **System Settings > General > Sharing**.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("2. Turn ON **File Sharing**, then click the **(ℹ️)** icon.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("3. Check the folder name in **Shared Folders** (e.g. 'Public') — enter this as the **Share Name**.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("4. Click **Options...**, check **'Share files using SMB'**, and check your user account.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(editingAccount != nil ? "Edit SMB Connection" : "Connect to SMB Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                bonjourBrowser.startDiscovery()
            }
            .onDisappear {
                bonjourBrowser.stopDiscovery()
            }
        }
    }
    
    private var isFormInvalid: Bool {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHost.isEmpty {
            return true
        }
        if !isGuest && username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }
    
    private func selectDiscoveredServer(_ server: DiscoveredSMBServer) {
        if let ip = server.ipAddress, !ip.isEmpty {
            self.host = ip
        } else {
            self.host = server.hostName
        }
        self.port = String(server.port)
        if self.serverName.isEmpty {
            self.serverName = server.name
        }
    }
    
    private func parseHostAndShareIfNeeded() {
        var cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If user typed smb://192.168.1.50/share
        if cleanHost.lowercased().hasPrefix("smb://") {
            cleanHost = String(cleanHost.dropFirst(6))
        }
        
        let parts = cleanHost.split(separator: "/")
        if parts.count >= 2 {
            self.host = String(parts[0])
            if self.share.isEmpty {
                self.share = String(parts[1])
            }
            if parts.count > 2 && self.basePath.isEmpty {
                self.basePath = parts[2...].joined(separator: "/")
            }
        } else {
            self.host = cleanHost
        }
    }
    
    private func buildConfiguration() -> SMBConfiguration {
        parseHostAndShareIfNeeded()
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPort = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 445
        let cleanShare = share.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPath = basePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPass = password
        let cleanDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return SMBConfiguration(
            host: cleanHost,
            port: cleanPort,
            share: cleanShare,
            basePath: cleanPath,
            username: cleanUser,
            password: cleanPass,
            domain: cleanDomain,
            isGuest: isGuest
        )
    }
    
    private func discoverShares() {
        isDiscoveringShares = true
        errorMessage = nil
        
        let config = buildConfiguration()
        let client = SMBClient(config: config)
        
        Task {
            do {
                let shares = try await client.listAvailableShares()
                await MainActor.run {
                    self.isDiscoveringShares = false
                    self.availableShares = shares
                }
            } catch {
                await MainActor.run {
                    self.isDiscoveringShares = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func testConnection() {
        isTesting = true
        testSuccess = nil
        errorMessage = nil
        
        let config = buildConfiguration()
        let client = SMBClient(config: config)
        
        Task {
            do {
                if config.share.isEmpty {
                    let shares = try await client.listAvailableShares()
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.availableShares = shares
                    }
                } else {
                    try await client.connect()
                    _ = try await client.listDirectory(path: config.basePath)
                    client.disconnect()
                    
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                    }
                }
            } catch {
                client.disconnect()
                await MainActor.run {
                    self.isTesting = false
                    self.testSuccess = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func saveAndConnect() {
        isConnecting = true
        errorMessage = nil
        
        let config = buildConfiguration()
        let client = SMBClient(config: config)
        
        Task {
            do {
                if config.share.isEmpty {
                    let shares = try await client.listAvailableShares()
                    await MainActor.run {
                        self.availableShares = shares
                    }
                } else {
                    try await client.connect()
                    _ = try await client.listDirectory(path: config.basePath)
                    client.disconnect()
                }
                
                let displayName: String
                if !serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayName = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if config.share.isEmpty {
                    displayName = config.host
                } else {
                    displayName = "\(config.host)/\(config.share)"
                }
                
                let accountId = editingAccount?.id ?? UUID().uuidString
                let createdAt = editingAccount?.createdAt ?? Date()
                
                let account = CloudAccount(
                    id: accountId,
                    providerId: SMBStorageProvider.providerId,
                    accountName: config.isGuest ? "Guest @ \(config.host)" : "\(config.username) @ \(config.host)",
                    displayName: displayName,
                    customProperties: [
                        "host": config.host,
                        "port": String(config.port),
                        "share": config.share,
                        "basePath": config.basePath,
                        "username": config.username,
                        "password": config.password,
                        "domain": config.domain,
                        "isGuest": config.isGuest ? "true" : "false"
                    ],
                    createdAt: createdAt
                )
                
                CloudAccountManager.shared.save(account: account)
                
                await MainActor.run {
                    self.isConnecting = false
                    self.onConnected?()
                    self.dismiss()
                }
            } catch {
                client.disconnect()
                await MainActor.run {
                    self.isConnecting = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
