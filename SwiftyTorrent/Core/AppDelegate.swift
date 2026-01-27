//
//  AppDelegate.swift
//  SwiftyTorrent
//
//  Created by Danylo Kostyshyn on 6/24/19.
//  Copyright © 2019 Danylo Kostyshyn. All rights reserved.
//

import UIKit
import AVFoundation
import BackgroundTasks

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var audioSession: AVAudioSession?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
//        setupBackgroundAudio()
//        setupBackgroudMode()
        return true
    }
    
    
    func setupBackgroundAudio() {
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession?.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession?.setActive(true)
            
            // Create a silent audio player to keep app alive
            guard let audioUrl = Bundle.main.url(forResource: "silence", withExtension: "mp3") else { return }
            let player = try AVAudioPlayer(contentsOf: audioUrl)
            player.numberOfLoops = -1 // Infinite loop
            player.volume = 0.0
            player.play()
        } catch {
            print("Failed to setup audio session: \(error.localizedDescription)")
        }
    }

    // MARK: UISceneSession Lifecycle

    @available(iOS 13.0, *)
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    @available(iOS 13.0, *)
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running,
        // this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

}
