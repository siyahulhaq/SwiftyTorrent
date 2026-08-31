//
//  AppCoordinator.swift
//  SwiftyTorrent
//
//  Created by Danylo Kostyshyn on 7/12/19.
//  Copyright © 2019 Danylo Kostyshyn. All rights reserved.
//

import UIKit
import SwiftUI
import Combine
import TorrentKit

protocol ApplicationCoordinator {

    func start()
    
}

@available(iOS 17.0, *)
final class AppCoordinator: ApplicationCoordinator {
    
    private var window: UIWindow!
    private var torrentManager: TorrentManagerProtocol {
        resolveComponent(TorrentManagerProtocol.self)
    }
    
    init(window: UIWindow) {
        self.window = window
    }
    
    func handleOpenURLContexts(_ URLContexts: Set<UIOpenURLContext>) {
        guard let URLContext = URLContexts.first else { return }
        torrentManager.open(URLContext.url)
    }

    // MARK: - ApplicationCoordinator
    
    func start() {
        registerDependencies()
        
        window.rootViewController = UIHostingController(rootView: MainView())
        window.makeKeyAndVisible()
        
        requestUserNotifications()
        
        // Prevent screen from dimming
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    // MARK: -
    
    private func requestUserNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (_, error) in
            if let error = error {
                print("\(error.localizedDescription)")
            }
        }
    }

}
