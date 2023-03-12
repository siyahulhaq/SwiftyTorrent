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

struct TorrentsView: View {
    @ObservedObject var model: TorrentsViewModel
    
    var body: some View {
        NavigationView {
            TorrentsList()
                .environmentObject(model)
        }
        .alert(isPresented: model.isPresentingAlert) { () -> Alert in
            Alert(error: model.activeError!)
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

struct TorrentsList: View {
    @EnvironmentObject var model: TorrentsViewModel
    @State var showAl = false
    @State var alertInfo: AlertInfo?
    
    func showAlert (_ deletable: Bool, _ torrent: Torrent) {
        let title = "Are you sure?"
        let message1 = "This will remove torrent"
        let message2 = "This will remove torrent and files"
        alertInfo = AlertInfo(id: deletable ? .two : .one, deleteFile: deletable, title: title, message: deletable ? message2 : message1, torrent: torrent)
        model.isPresentingRemoveAlert = true
        showAl = true
    }
    
    var body: some View {
        List {
            Section(header: Text("Downloads")) {
                ForEach(model.torrents, id: \.infoHash) { torrent in
                    NavigationLink(destination: FilesView(model: torrent.directory)) {
                        TorrentRow(model: torrent)
                    }.contextMenu {
                        Button(role: .destructive) {
                            self.showAlert(false, torrent)
                        } label: {
                            Label("Remove torrent", systemImage: "trash")
                        }
                        Button(role: .destructive) {
                            self.showAlert(true, torrent)
                        } label: {
                            Label("Remove Torrent and data", systemImage: "trash")
                        }
                    }.disabled(!torrent.hasMetadata)
                }
            }
#if DEBUG
            Section(header: Text("Debug")) {
                Button("Add test torrent files") {
                    model.addTestTorrentFiles()
                }
                Button("Add test magnet links") {
                    model.addTestMagnetLinks()
                }
                Button("Add all test torrents") {
                    model.addTestTorrents()
                }
            }
#if os(iOS)
            .buttonStyle(BlueButton())
#endif
#endif
        }
        .refreshable { model.reloadData() }
        .listStyle(PlainListStyle())
        .navigationBarTitle("Torrents")
        .alert(isPresented: $showAl, content: {
            if(self.alertInfo != nil) {
                return Alert(
                   title: Text(alertInfo!.title),
                   message: Text(alertInfo!.message),
                   primaryButton: .cancel(Text("Cancel")) {
                       model.isPresentingRemoveAlert = false
                   },
                   secondaryButton: .destructive(Text("Remove"), action: {
                       model.isPresentingRemoveAlert = false
                       model.remove(self.alertInfo!.torrent, deleteFiles: self.alertInfo!.deleteFile)
                   })
               )
            }
            return Alert(title: Text("Error"), dismissButton: .cancel(Text("Ok"),action: {
                        model.isPresentingRemoveAlert = false
                
            }) )
        })
    }
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
struct TorrentsView_Previews: PreviewProvider {
    static var previews: some View {
        // Use stubs
        registerStubs()
        let model = TorrentsViewModel()
        return TorrentsView(model: model).environment(\.colorScheme, .dark)
    }
}
#endif
