//
//  PlaybackRoute.swift
//  MediaKit
//
//  Defines the playback strategy selected for a media asset.
//

import Foundation

public enum PlaybackRoute {
    /// Native container (.mp4, .mov, .m4v) with native codecs.
    /// Handled directly by AVPlayer with zero remuxing overhead.
    case directAVPlayer(url: URL)
    
    /// MKV / TS container with compatible codecs (HEVC/H.264/DoVi + AAC/AC3/E-AC-3).
    /// Remuxed on the fly to fMP4/HLS and served via localhost to AVPlayer.
    /// Unlocks native hardware Dolby Vision and Dolby Atmos without transcoding.
    case transmuxedHLS(originalURL: URL, hlsURL: URL, server: LocalHLSServer)
    
    /// Incompatible codecs (e.g. DTS audio, TrueHD, VC-1 video, or legacy AVI).
    /// Handled by KSMEPlayer using FFmpeg VideoToolbox/Metal rendering pipeline.
    case ffmpegDirect(url: URL)
    
    public var playbackURL: URL {
        switch self {
        case .directAVPlayer(let url):
            return url
        case .transmuxedHLS(_, let hlsURL, _):
            return hlsURL
        case .ffmpegDirect(let url):
            return url
        }
    }
    
    public var isTransmuxed: Bool {
        if case .transmuxedHLS = self { return true }
        return false
    }
    
    public func cleanup() {
        if case .transmuxedHLS(_, _, let server) = self {
            server.stop()
        }
    }
}
