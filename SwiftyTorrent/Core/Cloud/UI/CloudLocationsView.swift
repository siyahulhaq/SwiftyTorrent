//
//  CloudLocationsView.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

public struct CloudLocationsView: View {
    @StateObject private var viewModel = CloudLocationsViewModel()
    @ObservedObject private var downloadManager = CloudDownloadManager.shared
    @State private var showDocumentPicker = false
    @State private var showGoogleDriveAuth = false
    @State private var showSMBAuth = false
    @State private var showDownloadsSheet = false
    @State private var accountToEdit: CloudAccount? = nil
    
    public init() {}
    
    public var body: some View {
        List {
            // MARK: - Downloads Section
            Section {
                NavigationLink(destination: DownloadsManagerView()) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Downloads Manager")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 4) {
                                if !downloadManager.activeTasks.isEmpty {
                                    Text("\(downloadManager.activeTasks.count) downloading...")
                                        .foregroundColor(.blue)
                                        .fontWeight(.medium)
                                } else {
                                    Text("\(downloadManager.completedFiles.count) files on device")
                                        .foregroundColor(.secondary)
                                }
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(downloadManager.formattedTotalDownloadedSize)
                                    .foregroundColor(.secondary)
                            }
                            .font(.system(size: 13))
                        }
                        
                        Spacer()
                        
                        if !downloadManager.activeTasks.isEmpty {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // MARK: - Locations Section
            Section(header: Text("Storage Locations")) {
                ForEach(viewModel.locations) { location in
                    NavigationLink(destination: CloudExplorerView(
                        provider: location.provider,
                        folderName: location.title
                    )) {
                        HStack(spacing: 14) {
                            Image(systemName: location.iconName)
                                .font(.system(size: 24))
                                .frame(width: 32, height: 32)
                                .foregroundColor(colorFromHex(location.brandColorHex))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(location.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Text(location.subtitle)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if let accountId = location.accountId, let account = CloudAccountManager.shared.account(for: accountId) {
                            Button(role: .destructive) {
                                viewModel.disconnectAccount(accountId)
                            } label: {
                                Label("Disconnect", systemImage: "trash")
                            }
                            
                            Button {
                                accountToEdit = account
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .contextMenu {
                        if let accountId = location.accountId, let account = CloudAccountManager.shared.account(for: accountId) {
                            Button {
                                accountToEdit = account
                            } label: {
                                Label("Edit Connection", systemImage: "pencil")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                viewModel.disconnectAccount(accountId)
                            } label: {
                                Label("Disconnect", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            
            // MARK: - Add Services Section
            Section(header: Text("Add Storage Service")) {
                Button(action: {
                    showDocumentPicker = true
                }) {
                    HStack(spacing: 14) {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 22))
                            .frame(width: 32, height: 32)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Link iCloud Drive Folder")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)
                            Text("Grant access to any folder on iCloud Drive")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                ForEach(viewModel.availableDescriptors.filter { $0.id != LocalStorageProvider.providerId && $0.id != ICloudStorageProvider.providerId }) { descriptor in
                    Button(action: {
                        if descriptor.id == GoogleDriveStorageProvider.providerId {
                            showGoogleDriveAuth = true
                        } else if descriptor.id == SMBStorageProvider.providerId {
                            showSMBAuth = true
                        } else {
                            Task {
                                await viewModel.connectProvider(descriptor)
                            }
                        }
                    }) {
                        HStack(spacing: 14) {
                            Image(systemName: descriptor.iconName)
                                .font(.system(size: 22))
                                .frame(width: 32, height: 32)
                                .foregroundColor(colorFromHex(descriptor.brandColorHex))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connect \(descriptor.displayName)")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(descriptor.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Files & Cloud")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: { showDownloadsSheet = true }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 20))
                            
                            if !downloadManager.activeTasks.isEmpty {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                    }
                    
                    Menu {
                        Button(action: { showDocumentPicker = true }) {
                            Label("Link iCloud Folder", systemImage: "icloud")
                        }
                        ForEach(viewModel.availableDescriptors.filter { $0.id != LocalStorageProvider.providerId && $0.id != ICloudStorageProvider.providerId }) { descriptor in
                            Button(action: {
                                if descriptor.id == GoogleDriveStorageProvider.providerId {
                                    showGoogleDriveAuth = true
                                } else if descriptor.id == SMBStorageProvider.providerId {
                                    showSMBAuth = true
                                } else {
                                    Task {
                                        await viewModel.connectProvider(descriptor)
                                    }
                                }
                            }) {
                                Label("Connect \(descriptor.displayName)", systemImage: descriptor.iconName)
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                    }
                }
            }
        }
        .sheet(isPresented: $showDownloadsSheet) {
            NavigationStack {
                DownloadsManagerView()
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerPresenter(contentTypes: [.folder]) { pickedURL in
                viewModel.addICloudFolder(url: pickedURL)
            }
        }
        .sheet(isPresented: $showGoogleDriveAuth) {
            GoogleDriveAuthSheet {
                viewModel.reloadLocations()
            }
        }
        .sheet(isPresented: $showSMBAuth) {
            SMBAuthSheet {
                viewModel.reloadLocations()
            }
        }
        .sheet(item: $accountToEdit) { account in
            if account.providerId == SMBStorageProvider.providerId {
                SMBAuthSheet(editingAccount: account) {
                    viewModel.reloadLocations()
                }
            } else if account.providerId == ICloudStorageProvider.providerId {
                ICloudEditSheet(account: account) {
                    viewModel.reloadLocations()
                }
            } else if account.providerId == GoogleDriveStorageProvider.providerId {
                GoogleDriveEditSheet(account: account) {
                    viewModel.reloadLocations()
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let err = viewModel.errorMessage {
                Text(err)
            }
        }
        .overlay {
            if viewModel.isAuthenticating {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Connecting...")
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 8)
                }
            }
        }
    }
    
    private func colorFromHex(_ hex: String) -> Color {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.remove(at: cleanHex.startIndex)
        }
        guard cleanHex.count == 6, let rgbValue = UInt64(cleanHex, radix: 16) else {
            return .blue
        }
        return Color(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }
}
