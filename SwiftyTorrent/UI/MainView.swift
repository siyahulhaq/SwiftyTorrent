//
//  MainView.swift
//  SwiftyTorrent
//
//  Created by Danylo Kostyshyn on 29.06.2020.
//  Copyright © 2020 Danylo Kostyshyn. All rights reserved.
//

import SwiftUI

extension View {
    @ViewBuilder func onlyStackView() -> some View {
        self.navigationViewStyle(.stack)
    }
}

struct MainView: View {
    
    var body: some View {
        TabView {
            TorrentsView(model: TorrentsViewModel())
                .tabItem {
                    Image(systemName: "square.and.arrow.down")
                    Text("Torrents")
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
