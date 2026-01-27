//
//  TorrentsView.swift
//  SwiftyTorrent
//
//  Created by Danylo Kostyshyn on 7/1/19.
//  Copyright © 2019 Danylo Kostyshyn. All rights reserved.
//

import SwiftUI
import Combine
import TorrentKit

@available(iOS 17.0, *)
struct TorrentsView: View {
    var model: TorrentsViewModel
    @State private var alertInfo: AlertInfo?
    @StateObject private var activityManager = ActivityManager.shared
    
    private func showAlert(deleteFiles: Bool, for torrent: Torrent) {
        let title = "Remove Torrent"
        let message = deleteFiles ?
        "Are you sure you want to remove this torrent and delete all downloaded files?" :
        "Are you sure you want to remove this torrent?"
        
        alertInfo = AlertInfo(
            id: deleteFiles ? .two : .one,
            deleteFile: deleteFiles,
            title: title,
            message: message,
            torrent: torrent
        )
    }
    
    var body: some View {
        NavigationView {
            List {
                torrentsSection
                //            #if DEBUG
                //            debugSection
                //            #endif
            }
            .refreshable { model.reloadData() }
            .listStyle(.plain)
            .navigationTitle("Torrents")
        }
        
        .alert(item: $alertInfo) { info in
            Alert(
                title: Text(info.title),
                message: Text(info.message),
                primaryButton: .cancel {
                    model.isPresentingRemoveAlert = false
                },
                secondaryButton: .destructive(Text("Remove")) {
                    model.isPresentingRemoveAlert = false
                    model.remove(info.torrent, deleteFiles: info.deleteFile)
                }
            )
        }
    }
    
    private var torrentsSection: some View {
        Section("Downloads") {
            ForEach(model.torrents, id: \.infoHash) { torrent in
                NavigationLink(destination: FilesView(model: torrent.directory)) {
                    TorrentRow(model: torrent)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        showAlert(deleteFiles: false, for: torrent)
                    } label: {
                        Label("Remove torrent", systemImage: "trash")
                    }
                    
                    Button(role: .destructive) {
                        showAlert(deleteFiles: true, for: torrent)
                    } label: {
                        Label("Remove Torrent and data", systemImage: "trash.fill")
                    }
                }
                .disabled(!torrent.hasMetadata)
            }
        }
    }
}

struct AlertInfo: Identifiable {
    enum AlertType {
        case one
        case two
    }
    
    let id: AlertType
    let deleteFile: Bool
    let title: String
    let message: String
    let torrent: Torrent
}

struct BlueButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.blue)
    }
}

extension Alert {
    init(error: Error) {
        self = Alert(
            title: Text("Error"),
            message: Text(error.localizedDescription),
            dismissButton: .default(Text("OK"))
        )
    }
}

#if DEBUG
@available(iOS 17.0, *)
struct TorrentsView_Previews: PreviewProvider {
    static var previews: some View {
        // Use stubs
        registerStubs()
        let model = TorrentsViewModel()
        return TorrentsView(model: model).environment(\.colorScheme, .dark)
    }
}
#endif
