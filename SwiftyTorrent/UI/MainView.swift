//
//  MainView.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 29.06.2026.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI

extension View {
    @ViewBuilder func onlyStackView() -> some View {
        #if os(iOS) || os(tvOS)
        self.navigationViewStyle(.stack)
        #else
        self
        #endif
    }
    
    @ViewBuilder func inlineNavigationBarTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    
    @ViewBuilder func groupedListStyleIfAvailable() -> some View {
        #if os(iOS)
        self.listStyle(InsetGroupedListStyle())
        #else
        self.listStyle(.automatic)
        #endif
    }
    
    @ViewBuilder func disableAutocapitalizationIfAvailable() -> some View {
        #if os(iOS) || os(tvOS)
        self.autocapitalization(.none)
            .disableAutocorrection(true)
        #else
        self
        #endif
    }
}

@available(iOS 17.0, *)
struct MainView: View {
    
    var body: some View {
        TabView {
            TorrentsView(model: TorrentsViewModel())
                .tabItem {
                    Image(systemName: "square.and.arrow.down")
                    Text("Torrents")
                }
            FilesExplorerView()
                .tabItem {
                    Image(systemName: "folder")
                    Text("Files")
                }
                
            SearchView(model: SearchViewModel())
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
            SettingsView(model: SettingsViewModel())
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }.onlyStackView()
    }
}
