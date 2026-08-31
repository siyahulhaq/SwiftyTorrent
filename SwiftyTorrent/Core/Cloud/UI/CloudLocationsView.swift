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
    
    @State private var showDocumentPicker = false
    @State private var showGoogleDriveAuth = false
    @State private var showAddServiceSheet = false
    
    public init() {}
    
    public var body: some View {
        List {
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
                        if let accountId = location.accountId {
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
                Menu {
                    Button(action: { showDocumentPicker = true }) {
                        Label("Link iCloud Folder", systemImage: "icloud")
                    }
                    ForEach(viewModel.availableDescriptors.filter { $0.id != LocalStorageProvider.providerId && $0.id != ICloudStorageProvider.providerId }) { descriptor in
                        Button(action: {
                            if descriptor.id == GoogleDriveStorageProvider.providerId {
                                showGoogleDriveAuth = true
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
