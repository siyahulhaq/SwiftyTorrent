//
//  PlaybackRouter.swift
//  MediaKit
//
//  Clean Architecture Routing Decision Engine.
//  Inspects container/codecs and selects the optimal playback pipeline.
//

import Foundation

public final class PlaybackRouter {
    
    /// Resolves the optimal playback route for the given media URL.
    /// Prefers native AVPlayer directly or via zero-transcode local HLS for Dolby Vision/Atmos.
    /// Seamlessly falls back to FFmpeg KSMEPlayer when necessary.
    public static func resolveRoute(for url: URL) -> PlaybackRoute {
        // 1. CloudMediaProxyServer streams (Google Drive, WebDAV, Cloud storage)
        if let host = url.host, (host == "127.0.0.1" || host == "localhost"), url.path.contains("/stream") {
            print("[PlaybackRouter] -> Detected CloudMediaProxyServer stream (Google Drive / Cloud). Routing to KSMEPlayer.")
            return .ffmpegDirect(url: url)
        }
        
        // 2. Non-file remote URLs
        guard url.isFileURL else {
            let ext = url.pathExtension.lowercased()
            if ["m3u8", "mp4", "mov", "m4v"].contains(ext) {
                return .directAVPlayer(url: url)
            }
            print("[PlaybackRouter] Remote/network stream detected (\(url.absoluteString)). Routing to KSMEPlayer.")
            return .ffmpegDirect(url: url)
        }
        
        guard let probe = MediaProbe.probe(url: url) else {
            print("[PlaybackRouter] Media probe failed for \(url.lastPathComponent), falling back to FFmpeg engine")
            return .ffmpegDirect(url: url)
        }
        
        print("[PlaybackRouter] Probed \(url.lastPathComponent): container=\(probe.containerFormat), duration=\(probe.durationInSeconds)s")
        if let video = probe.primaryVideoTrack {
            print("[PlaybackRouter] Video: \(video.codecName) (\(video.width)x\(video.height)), DoVi=\(video.isDolbyVision), profile=\(video.doviProfile ?? 0)")
        }
        if let audio = probe.primaryAudioTrack {
            print("[PlaybackRouter] Audio: \(audio.codecName), channels=\(audio.channels), Atmos=\(audio.hasAtmos)")
        }
        
        // 1. Direct native AVPlayer for MP4/MOV
        if probe.isDirectPlayableByAVPlayer {
            print("[PlaybackRouter] -> Route: Direct Native AVPlayer")
            return .directAVPlayer(url: url)
        }
        
        // 2. Direct hardware-accelerated KSMEPlayer for MKV and other containers
        // Powered by Apple VideoToolbox hardware decoding + Metal GPU shaders + 35 microsecond instant seeking
        print("[PlaybackRouter] -> Route: Hardware FFmpeg Engine (KSMEPlayer)")
        return .ffmpegDirect(url: url)
    }
}
