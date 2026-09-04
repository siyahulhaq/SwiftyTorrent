//
//  FilesView.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 7/16/19.
//  Copyright © 2019 Siyahul Haq. All rights reserved.
//

import SwiftUI
import MediaKit

public enum FileSortField: String, CaseIterable, Identifiable {
    case name = "Name"
    case dateModified = "Date Modified"
    case dateCreated = "Date Created"
    case dateOpened = "Date Last Opened"
    case size = "Size"
    case type = "Type"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .name: return "textformat"
        case .dateModified: return "calendar.badge.clock"
        case .dateCreated: return "calendar.badge.plus"
        case .dateOpened: return "clock.arrow.circlepath"
        case .size: return "arrow.up.arrow.down"
        case .type: return "square.grid.2x2"
        }
    }
}

public enum FileSortOrder: String, CaseIterable, Identifiable {
    case ascending = "Ascending"
    case descending = "Descending"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .ascending: return "arrow.up"
        case .descending: return "arrow.down"
        }
    }
}

struct FilesView: View {
    
    var model: FilesViewModel
    @State var selectedItem: File?
    @State var selectedVideo: File?
    
    @State private var searchText = ""
    @AppStorage("files_sort_field") private var sortField: FileSortField = .name
    @AppStorage("files_sort_order") private var sortOrder: FileSortOrder = .ascending
    
    private var filteredSubDirectories: [Directory] {
        let list: [Directory]
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            list = model.directory.allSubDirectories
        } else {
            list = model.directory.allSubDirectories.filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
        }
        
        return list.sorted { lhs, rhs in
            sortComparison(lhs: lhs, rhs: rhs)
        }
    }
    
    private var filteredFiles: [File] {
        let list: [File]
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            list = model.directory.allFiles
        } else {
            list = model.directory.allFiles.filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
        }
        
        return list.sorted { lhs, rhs in
            sortComparison(lhs: lhs, rhs: rhs)
        }
    }
    
    private func sortComparison(lhs: FileProtocol, rhs: FileProtocol) -> Bool {
        let isAscending = (sortOrder == .ascending)
        
        switch sortField {
        case .name:
            let result = lhs.name.localizedStandardCompare(rhs.name)
            return isAscending ? (result == .orderedAscending) : (result == .orderedDescending)
            
        case .dateModified:
            let lDate = lhs.modifiedAt ?? Date.distantPast
            let rDate = rhs.modifiedAt ?? Date.distantPast
            if lDate == rDate {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return isAscending ? (lDate < rDate) : (lDate > rDate)
            
        case .dateCreated:
            let lDate = lhs.createdAt ?? Date.distantPast
            let rDate = rhs.createdAt ?? Date.distantPast
            if lDate == rDate {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return isAscending ? (lDate < rDate) : (lDate > rDate)
            
        case .dateOpened:
            let lDate = lhs.accessedAt ?? Date.distantPast
            let rDate = rhs.accessedAt ?? Date.distantPast
            if lDate == rDate {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return isAscending ? (lDate < rDate) : (lDate > rDate)
            
        case .size:
            if lhs.size == rhs.size {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return isAscending ? (lhs.size < rhs.size) : (lhs.size > rhs.size)
            
        case .type:
            if lhs.fileCategory == rhs.fileCategory {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return isAscending ? (lhs.fileCategory < rhs.fileCategory) : (lhs.fileCategory > rhs.fileCategory)
        }
    }
    
    private var isDirectoryEmpty: Bool {
        model.directory.allSubDirectories.isEmpty && model.directory.allFiles.isEmpty
    }
    
    private var isSearchEmpty: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        filteredSubDirectories.isEmpty &&
        filteredFiles.isEmpty
    }

    var body: some View {
        Group {
            if isDirectoryEmpty {
                emptyDirectoryView
            } else if isSearchEmpty {
                emptySearchView
            } else {
                fileListView
            }
        }
        #if os(iOS)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search in \(navigationTitleText)"
        )
        #else
        .searchable(
            text: $searchText,
            prompt: "Search in \(navigationTitleText)"
        )
        #endif
        #if os(iOS)
        .navigationBarTitle(navigationTitleText, displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                sortMenu
            }
        }
        #else
        .navigationTitle(navigationTitleText)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                sortMenu
            }
        }
        #endif
        .sheet(item: $selectedItem) { item in
            NavigationView {
                Group {
                    #if os(iOS)
                    QLViewHost(previewItem: item)
                    #else
                    Text("Not Supported")
                    Spacer()
                    Text(item.name)
                    #endif
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { selectedItem = nil }
                    }
                }
                #if os(iOS)
                .navigationBarTitle(item.name, displayMode: .inline)
                #else
                .navigationTitle(item.name)
                #endif
            }
        }
        #if os(macOS)
        .sheet(item: $selectedVideo) { item in
            MediaPlayerViewHost(previewItem: item)
                .frame(minWidth: 700, minHeight: 450)
        }
        #else
        .fullScreenCover(item: $selectedVideo) { item in
            MediaPlayerViewHost(previewItem: item)
                .ignoresSafeArea(.all)
        }
        #endif
    }
    
    // MARK: - Subviews
    
    private var fileListView: some View {
        List {
            if !filteredSubDirectories.isEmpty {
                Section(header: Text("Folders (\(filteredSubDirectories.count))")) {
                    ForEach(filteredSubDirectories, id: \.path) { subDir in
                        NavigationLink(destination: FilesView(model: subDir)) {
                            FileRow(model: subDir, dateSortField: sortField)
                        }
                    }
                }
            }
            
            if !filteredFiles.isEmpty {
                Section(header: Text("Files (\(filteredFiles.count))")) {
                    ForEach(filteredFiles, id: \.path) { item in
                        Button(action: {
                            if item.isVideo {
                                self.selectedVideo = item
                            } else {
                                self.selectedItem = item
                            }
                        }) {
                            FileRow(model: item, dateSortField: sortField)
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            
            // Summary footer
            Section {
                HStack {
                    Spacer()
                    Text(summaryFooterText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .groupedListStyleIfAvailable()
    }
    
    private var emptyDirectoryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text("Folder is Empty")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("No files or subfolders found in this directory.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptySearchView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 54))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text("No Results for \"\(searchText)\"")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Check the spelling or try a different search term.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var sortMenu: some View {
        Menu {
            Section(header: Text("Sort By")) {
                ForEach(FileSortField.allCases) { field in
                    Button(action: {
                        sortField = field
                    }) {
                        if sortField == field {
                            Label(field.rawValue, systemImage: "checkmark")
                        } else {
                            Label(field.rawValue, systemImage: field.iconName)
                        }
                    }
                }
            }
            
            Section(header: Text("Order")) {
                ForEach(FileSortOrder.allCases) { order in
                    Button(action: {
                        sortOrder = order
                    }) {
                        if sortOrder == order {
                            Label(order.rawValue, systemImage: "checkmark")
                        } else {
                            Label(order.rawValue, systemImage: order.iconName)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .imageScale(.large)
        }
    }
    
    private var navigationTitleText: String {
        let t = model.title
        if t.isEmpty || t == "/" {
            return "Files"
        }
        return t
    }
    
    private var summaryFooterText: String {
        let totalItems = filteredSubDirectories.count + filteredFiles.count
        let totalBytes = filteredSubDirectories.reduce(0) { $0 + $1.size } + filteredFiles.reduce(0) { $0 + $1.size }
        let itemString = totalItems == 1 ? "1 item" : "\(totalItems) items"
        if totalBytes > 0 {
            let sizeString = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
            return "\(itemString) • \(sizeString)"
        }
        return itemString
    }
}
