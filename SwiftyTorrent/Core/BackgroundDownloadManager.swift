//
//  BackgroundDownloadManager.swift
//  SwiftyTorrent
//
//  Background download support for iOS 13+ with iOS 26 BGContinuedProcessingTask
//

import UIKit
import BackgroundTasks
import TorrentKit

/// Manages background download tasks for torrents
/// Uses BGContinuedProcessingTask (iOS 26+) for extended background execution
/// Falls back to BGProcessingTask for iOS 13-25
final class BackgroundDownloadManager {
    
    static let shared = BackgroundDownloadManager()
    
    /// Task identifier for continued processing (iOS 26+)
    static let continuedTaskIdentifier = "com.swiftytorrent.download.continued"
    
    /// Task identifier for processing downloads (iOS 13-25)
    static let processingTaskIdentifier = "com.swiftytorrent.download.processing"
    
    private var isRegistered = false
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    
    private init() {}
    
    // MARK: - Registration
    
    /// Register background tasks with the system. Call this in AppDelegate's didFinishLaunching.
    func registerBackgroundTasks() {
        guard !isRegistered else { return }
        
        if #available(iOS 26.0, *) {
            // Register continued processing task for iOS 26+
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Self.continuedTaskIdentifier,
                using: nil
            ) { [weak self] task in
                self?.handleContinuedProcessingTask(task as! BGContinuedProcessingTask)
            }
            print("[BackgroundDownloadManager] Registered BGContinuedProcessingTask for iOS 26+")
        } else if #available(iOS 13.0, *) {
            // Register processing task for iOS 13-25
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Self.processingTaskIdentifier,
                using: nil
            ) { [weak self] task in
                self?.handleProcessingTask(task as! BGProcessingTask)
            }
            print("[BackgroundDownloadManager] Registered BGProcessingTask for iOS 13-25")
        }
        
        isRegistered = true
    }
    
    // MARK: - Scheduling
    
    /// Schedule a background download task. Call this when the app enters background.
    func scheduleBackgroundDownload() {
        if #available(iOS 26.0, *) {
            scheduleContinuedProcessingTask()
        } else if #available(iOS 13.0, *) {
            scheduleProcessingTask()
        }
    }
    
    @available(iOS 26.0, *)
    private func scheduleContinuedProcessingTask() {
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedTaskIdentifier,
            title: "Downloading Torrents",
            subtitle: "Background download in progress"
        )
        
        // BGContinuedProcessingTask provides extended background execution
        // with user-visible progress
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundDownloadManager] Scheduled BGContinuedProcessingTask")
        } catch {
            print("[BackgroundDownloadManager] Failed to schedule continued task: \(error)")
        }
    }
    
    @available(iOS 13.0, *)
    private func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = nil
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundDownloadManager] Scheduled BGProcessingTask")
        } catch {
            print("[BackgroundDownloadManager] Failed to schedule processing task: \(error)")
        }
    }
    
    /// Cancel any pending background download tasks
    func cancelBackgroundDownload() {
        if #available(iOS 26.0, *) {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.continuedTaskIdentifier)
        } else if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.processingTaskIdentifier)
        }
        print("[BackgroundDownloadManager] Cancelled pending download tasks")
    }
    
    // MARK: - Immediate Background Task
    
    /// Start an immediate background task for short background execution
    func beginBackgroundTask() {
        guard backgroundTaskIdentifier == .invalid else { return }
        
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        
        if backgroundTaskIdentifier != .invalid {
            print("[BackgroundDownloadManager] Started immediate background task")
        }
    }
    
    /// End the immediate background task
    func endBackgroundTask() {
        guard backgroundTaskIdentifier != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
        print("[BackgroundDownloadManager] Ended immediate background task")
    }
    
    // MARK: - iOS 26+ Continued Processing Task Handling
    
    @available(iOS 26.0, *)
    private func handleContinuedProcessingTask(_ task: BGContinuedProcessingTask) {
        print("[BackgroundDownloadManager] Handling BGContinuedProcessingTask - extended background execution")
        
        // Set up expiration handler
        task.expirationHandler = { [weak self] in
            self?.handleContinuedTaskExpiration(task)
        }
        
        // Ensure torrent session is active
        let torrentManager = TorrentManager.shared()
        if !torrentManager.isSessionActive {
            torrentManager.restoreSession()
        }
        
        // Monitor downloads with progress reporting
        monitorContinuedDownloads(task: task)
    }
    
    @available(iOS 26.0, *)
    private func monitorContinuedDownloads(task: BGContinuedProcessingTask) {
        let torrentManager = TorrentManager.shared()
        let torrents = torrentManager.torrents()
        
        // Check if there are any active downloads
        let activeDownloads = torrents.filter { torrent in
            torrent.state == .downloading || torrent.state == .downloadingMetadata
        }
        
        if activeDownloads.isEmpty {
            // No active downloads, complete the task
            task.setTaskCompleted(success: true)
            print("[BackgroundDownloadManager] Continued task completed - no active downloads")
        } else {
            // Update progress for user visibility
            let totalProgress = activeDownloads.reduce(0.0) { $0 + $1.progress } / Double(activeDownloads.count)
            task.progress.totalUnitCount = 100
            task.progress.completedUnitCount = Int64(totalProgress * 100)
            
            // Update Live Activities
            Task {
                await updateLiveActivitiesForActiveDownloads()
            }
            
            // Continue monitoring - BGContinuedProcessingTask allows longer execution
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) { [weak self] in
                self?.monitorContinuedDownloads(task: task)
            }
        }
    }
    
    @available(iOS 26.0, *)
    private func handleContinuedTaskExpiration(_ task: BGContinuedProcessingTask) {
        print("[BackgroundDownloadManager] Continued task expiring - saving session state")
        task.setTaskCompleted(success: false)
    }
    
    // MARK: - iOS 13-25 Processing Task Handling
    
    @available(iOS 13.0, *)
    private func handleProcessingTask(_ task: BGProcessingTask) {
        print("[BackgroundDownloadManager] Handling BGProcessingTask - limited background time")
        
        // Schedule next task before completing this one
        scheduleProcessingTask()
        
        // Set up expiration handler
        task.expirationHandler = { [weak self] in
            self?.handleProcessingTaskExpiration(task)
        }
        
        // Ensure torrent session is active
        let torrentManager = TorrentManager.shared()
        if !torrentManager.isSessionActive {
            torrentManager.restoreSession()
        }
        
        // Monitor download progress
        monitorProcessingDownloads(task: task)
    }
    
    @available(iOS 13.0, *)
    private func monitorProcessingDownloads(task: BGProcessingTask) {
        let torrentManager = TorrentManager.shared()
        let torrents = torrentManager.torrents()
        
        // Check if there are any active downloads
        let hasActiveDownloads = torrents.contains { torrent in
            torrent.state == .downloading || torrent.state == .downloadingMetadata
        }
        
        if !hasActiveDownloads {
            task.setTaskCompleted(success: true)
            print("[BackgroundDownloadManager] Processing task completed - no active downloads")
        } else {
            // Update Live Activities
            Task {
                await updateLiveActivitiesForActiveDownloads()
            }
            
            // Check again in 30 seconds (processing tasks have limited time)
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.monitorProcessingDownloads(task: task)
            }
        }
    }
    
    @available(iOS 13.0, *)
    private func handleProcessingTaskExpiration(_ task: BGProcessingTask) {
        print("[BackgroundDownloadManager] Processing task expiring")
        task.setTaskCompleted(success: false)
    }
}

// MARK: - Scene Lifecycle Integration

extension BackgroundDownloadManager {
    
    /// Called when app enters background
    func applicationDidEnterBackground() {
        // Start immediate background task first
        beginBackgroundTask()
        
        // Schedule longer background task
        scheduleBackgroundDownload()
        
        // Start Live Activity for active downloads
        Task {
            await startLiveActivityForActiveDownloads()
        }
    }
    
    /// Called when app enters foreground
    func applicationWillEnterForeground() {
        // Cancel scheduled background tasks since we're in foreground
        cancelBackgroundDownload()
        
        // End any running background task
        endBackgroundTask()
        
        // Dismiss all Live Activities
        Task {
            await ActivityManager.shared.endAllActivities()
        }
    }
    
    // MARK: - Live Activity Management
    
    private func startLiveActivityForActiveDownloads() async {
        let torrentManager = TorrentManager.shared()
        let torrents = torrentManager.torrents()
        
        let activeDownloads = torrents.filter { torrent in
            torrent.state == .downloading || torrent.state == .downloadingMetadata
        }
        
        print("[BackgroundDownloadManager] Starting Live Activities for \(activeDownloads.count) active downloads")
        
        for torrent in activeDownloads {
            await ActivityManager.shared.startActivity(for: torrent)
        }
    }
    
    private func updateLiveActivitiesForActiveDownloads() async {
        let torrentManager = TorrentManager.shared()
        let torrents = torrentManager.torrents()
        
        let activeDownloads = torrents.filter { torrent in
            torrent.state == .downloading || torrent.state == .downloadingMetadata
        }
        
        for torrent in activeDownloads {
            await ActivityManager.shared.updateActivity(with: torrent)
        }
    }
}
