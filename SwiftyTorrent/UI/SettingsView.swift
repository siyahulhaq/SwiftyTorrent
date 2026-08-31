//
//  SettingsView.swift
//  SwiftyTorrent
//
//  Created by Danylo Kostyshyn on 15.06.2021.
//  Copyright © 2021 Danylo Kostyshyn. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        NavigationView {
            List {
                Section("Search") {
                    SettingsRow(title: "EZTV enpoint", value: $model.eztvEndpoint)
                }
                Section("Storage") {
                    SettingsRow(title: "Available", value: $model.availableDiskSpace)
                    SettingsRow(title: "Downloads size", value: $model.usedDiskSpace)
                    SettingsActionRow(title: "Remove all downloads", role: .destructive) {
                        model.removeAllDownloads()
                    }
                }
                #if os(iOS)
                Section(header: Text("Background Downloads"), footer: Text("Allows torrents to continue downloading while the app is in the background using continuous audio keep-alive.")) {
                    Toggle("Background Download", isOn: $model.backgroundDownloadEnabled)
                    Toggle("Background Seeding", isOn: $model.backgroundSeedingEnabled)
                }
                #endif
                Section("About") {
                    SettingsRow(title: "Version", value: $model.appVersion)
                }
            }
            .onAppear { model.reloadData() }
            .refreshable { model.reloadData() }
            .listStyle(GroupedListStyle())
            .navigationTitle("Settings")
        }
    }

}

struct SettingsRow: View {
    
    let title: String
    @Binding var value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.gray)
        }
    }
    
}

struct SettingsActionRow: View {
    
    let title: String
    let role: ButtonRole?
    let action: () -> Void
    
    var body: some View {
        HStack {
            Spacer()
            Button(title, role: role, action: action)
            Spacer()
        }
    }
    
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(model: SettingsViewModel())
    }
}
#endif
