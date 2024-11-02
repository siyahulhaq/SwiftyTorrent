//
//  BindableTorrentManager.swift
//  SwiftyTorrent
//
//  Created by Danylo Kostyshyn on 7/12/19.
//  Copyright © 2019 Danylo Kostyshyn. All rights reserved.
//

import Combine
import SwiftUI
import TorrentKit

final class TorrentsViewModel: NSObject, ObservableObject, TorrentManagerDelegate {
    
    private let torrentManager = resolveComponent(TorrentManagerProtocol.self)

    @Published private(set) var torrents = [Torrent]()

    @Published private(set) var showAlert: AlertInfo?

    @Published private(set) var activeError: Error?
    
    // Add a timer to throttle UI updates
    private var updateTimer: Timer?
    private var pendingTorrents: [Torrent]?
    private let updateInterval: TimeInterval = 1.0 // Update UI every second
    
    var isPresentingAlert: Binding<Bool> {
        return Binding<Bool>(get: {
            return self.activeError != nil
        }, set: { newValue in
            guard !newValue else { return }
            self.activeError = nil
        })
    }
    
    var isPresentingRemoveAlert: Bool = false
    
    override init() {
        super.init()
        torrentManager.addDelegate(self)
        setupUpdateTimer()
        reloadData()
    }
    
    private func setupUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.processPendingUpdates()
        }
    }
    
    private func processPendingUpdates() {
        guard let pending = pendingTorrents else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Only update if there are actual changes
            if !self.areArraysEqual(self.torrents, pending) {
                self.torrents = pending.sorted(by: { $0.name < $1.name })
            }
            self.pendingTorrents = nil
        }
    }
    
    private func areArraysEqual(_ current: [Torrent], _ new: [Torrent]) -> Bool {
        guard current.count == new.count else { return false }
        
        // Compare relevant properties that affect UI
        return zip(current, new).allSatisfy { currentTorrent, newTorrent in
            return currentTorrent.infoHash == newTorrent.infoHash &&
                   currentTorrent.progress == newTorrent.progress &&
                   currentTorrent.state == newTorrent.state &&
                   currentTorrent.downloadRate == newTorrent.downloadRate &&
                   currentTorrent.uploadRate == newTorrent.uploadRate &&
                   currentTorrent.numberOfPeers == newTorrent.numberOfPeers &&
                   currentTorrent.numberOfSeeds == newTorrent.numberOfSeeds
        }
    }
    
    func reloadData() {
        guard !isPresentingRemoveAlert else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let sortedTorrents = self.torrentManager.torrents()
                .sorted(by: { $0.name < $1.name })
            
            DispatchQueue.main.async {
                self.torrents = sortedTorrents
            }
        }
    }
    
    func remove(_ torrent: Torrent, deleteFiles: Bool = false) {
        torrentManager.removeTorrent(withInfoHash: torrent.infoHash, deleteFiles: deleteFiles)
    }
    
    func pause(_ torrent: Torrent) {
        
    }
    
    // MARK: - TorrentManagerDelegate
    
    func torrentManager(_ manager: TorrentManager, didAdd torrent: Torrent) {
        reloadData()
    }
    
    func torrentManager(_ manager: TorrentManager, didRemoveTorrentWithHash hashData: Data) {
        reloadData()
    }
    
    func torrentManager(_ manager: TorrentManager, didErrorOccur error: Error) {
        DispatchQueue.main.async {
            self.activeError = error
        }
    }
    
    func torrentManager(_ manager: TorrentManager, didReceiveUpdatesFor torrents: [Torrent]) {
        // Store updates in pending queue instead of updating immediately
        pendingTorrents = torrents
    }
    
    deinit {
        updateTimer?.invalidate()
        updateTimer = nil
        torrentManager.removeDelegate(self)
    }
    
}

#if DEBUG
extension TorrentsViewModel {

    func addTestTorrentFiles() {
        torrentManager.add(TorrentFile.test_1())
        torrentManager.add(TorrentFile.test_2())
    }
    
    func addTestMagnetLinks() {
        torrentManager.add(MagnetURI.test_1())
    }
    
    func addTestTorrents() {
        addTestTorrentFiles()
        addTestMagnetLinks()
    }
    
}
#endif
