//
//  CloudExplorerViewModel.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI
import Combine
import MediaKit

@MainActor
public final class CloudExplorerViewModel: ObservableObject {
    public let provider: CloudStorageProviderProtocol
    public let folderId: String?
    public let folderName: String
    
    @Published public var items: [CloudFileItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var searchText: String = ""
    @Published public var sortField: FileSortField = .name
    @Published public var sortOrder: FileSortOrder = .ascending
    
    public init(provider: CloudStorageProviderProtocol, folderId: String? = nil, folderName: String? = nil) {
        self.provider = provider
        self.folderId = folderId
        self.folderName = folderName ?? provider.descriptor.displayName
    }
    
    public var filteredDirectories: [CloudFileItem] {
        let directories = items.filter { $0.isDirectory }
        return filterAndSort(list: directories)
    }
    
    public var filteredFiles: [CloudFileItem] {
        let files = items.filter { !$0.isDirectory }
        return filterAndSort(list: files)
    }
    
    private func filterAndSort(list: [CloudFileItem]) -> [CloudFileItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [CloudFileItem]
        if query.isEmpty {
            filtered = list
        } else {
            filtered = list.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        
        let isAsc = (sortOrder == .ascending)
        return filtered.sorted { lhs, rhs in
            switch sortField {
            case .name:
                let res = lhs.name.localizedStandardCompare(rhs.name)
                return isAsc ? (res == .orderedAscending) : (res == .orderedDescending)
            case .dateModified:
                let lDate = lhs.modifiedAt ?? Date.distantPast
                let rDate = rhs.modifiedAt ?? Date.distantPast
                return isAsc ? (lDate < rDate) : (lDate > rDate)
            case .dateCreated:
                let lDate = lhs.createdAt ?? Date.distantPast
                let rDate = rhs.createdAt ?? Date.distantPast
                return isAsc ? (lDate < rDate) : (lDate > rDate)
            case .dateOpened:
                let lDate = lhs.accessedAt ?? Date.distantPast
                let rDate = rhs.accessedAt ?? Date.distantPast
                return isAsc ? (lDate < rDate) : (lDate > rDate)
            case .size:
                return isAsc ? (lhs.size < rhs.size) : (lhs.size > rhs.size)
            case .type:
                let lExt = (lhs.name as NSString).pathExtension.lowercased()
                let rExt = (rhs.name as NSString).pathExtension.lowercased()
                let res = lExt.localizedStandardCompare(rExt)
                return isAsc ? (res == .orderedAscending) : (res == .orderedDescending)
            }
        }
    }
    
    @MainActor
    public func loadContents() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await provider.listFolder(folderId: folderId, cursor: nil)
            self.items = result.items
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    public func deleteItem(_ item: CloudFileItem) async {
        do {
            try await provider.delete(item: item)
            self.items.removeAll { $0.id == item.id }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    public func preparePlayback(for item: CloudFileItem) async -> PreviewItem? {
        print("[CloudExplorerViewModel] preparePlayback called for item '\(item.name)'")
        do {
            let result = try await CloudPlaybackCoordinator.shared.prepareForPlayback(item: item, provider: provider)
            print("[CloudExplorerViewModel] CloudPlaybackCoordinator returned: \(result.previewItemTitle ?? "nil"), URL: \(result.previewItemURL?.absoluteString ?? "nil")")
            return result
        } catch {
            print("[CloudExplorerViewModel] ERROR during preparePlayback: \(error)")
            await MainActor.run {
                self.errorMessage = "Playback failed: \(error.localizedDescription)"
            }
            return nil
        }
    }
}
