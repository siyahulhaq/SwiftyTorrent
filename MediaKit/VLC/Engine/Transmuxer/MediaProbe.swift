//
//  MediaProbe.swift
//  MediaKit
//
//  Clean Architecture Media Probe & Stream Analyzer using FFmpeg libavformat.
//

import Foundation
import Libavformat
import Libavcodec
import Libavutil

// MARK: - Models

public struct MediaProbeResult {
    public let url: URL
    public let containerFormat: String
    public let durationInSeconds: Double
    public let videoTracks: [ProbeVideoTrack]
    public let audioTracks: [ProbeAudioTrack]
    public let subtitleTracks: [ProbeSubtitleTrack]
    
    /// Primary video track (first video stream)
    public var primaryVideoTrack: ProbeVideoTrack? {
        videoTracks.first
    }
    
    /// Primary audio track (first enabled/default audio stream)
    public var primaryAudioTrack: ProbeAudioTrack? {
        audioTracks.first(where: { $0.isDefault }) ?? audioTracks.first
    }
    
    /// Can Apple's native AVPlayer play this container directly without remuxing?
    public var isDirectPlayableByAVPlayer: Bool {
        let ext = url.pathExtension.lowercased()
        let nativeExtensions = ["mp4", "m4v", "mov"]
        guard nativeExtensions.contains(ext) else { return false }
        
        let videoOk = primaryVideoTrack?.isAVPlayerCompatible ?? true
        let audioOk = primaryAudioTrack?.isAVPlayerCompatible ?? true
        return videoOk && audioOk
    }
    
    /// Can this file be transmuxed on-the-fly (fMP4 / HLS) for native AVPlayer playback?
    /// This unlocks native hardware Dolby Vision and Dolby Atmos without video transcoding.
    public var isTransmuxPlayableForAVPlayer: Bool {
        guard let video = primaryVideoTrack else { return false }
        guard video.isAVPlayerCompatible else { return false }
        
        // Needs at least one audio track compatible with AVPlayer (AAC, AC3, E-AC3)
        // If there is no audio track (silent video), transmuxing is still supported.
        if audioTracks.isEmpty {
            return true
        }
        return audioTracks.contains(where: { $0.isAVPlayerCompatible })
    }
}

public struct ProbeVideoTrack {
    public let index: Int32
    public let codecID: AVCodecID
    public let codecName: String
    public let width: Int32
    public let height: Int32
    public let frameRate: Double
    public let bitDepth: Int32
    public let isDolbyVision: Bool
    public let doviProfile: UInt8?
    public let doviLevel: UInt8?
    
    public var isHEVC: Bool {
        codecID == AV_CODEC_ID_HEVC
    }
    
    public var isH264: Bool {
        codecID == AV_CODEC_ID_H264
    }
    
    /// AVPlayer natively decodes H.264, HEVC (including DoVi Profile 5 & Profile 8)
    public var isAVPlayerCompatible: Bool {
        if isH264 { return true }
        if isHEVC {
            // If Dolby Vision, profiles 5 and 8 are fully supported by Apple's VideoToolbox.
            // Profile 7 (dual-layer UHD Blu-ray) fallback is handled via single-layer conversion.
            return true
        }
        return false
    }
}

public struct ProbeAudioTrack {
    public let index: Int32
    public let codecID: AVCodecID
    public let codecName: String
    public let language: String?
    public let title: String?
    public let channels: Int32
    public let sampleRate: Int32
    public let isDefault: Bool
    public let hasAtmos: Bool
    
    public var isAAC: Bool {
        codecID == AV_CODEC_ID_AAC
    }
    
    public var isAC3: Bool {
        codecID == AV_CODEC_ID_AC3
    }
    
    public var isEAC3: Bool {
        codecID == AV_CODEC_ID_EAC3
    }
    
    /// Formats that AVPlayer can decode or passthrough natively in fMP4
    public var isAVPlayerCompatible: Bool {
        isAAC || isAC3 || isEAC3 || codecID == AV_CODEC_ID_ALAC || codecID == AV_CODEC_ID_PCM_S16LE
    }
}

public struct ProbeSubtitleTrack {
    public let index: Int32
    public let codecID: AVCodecID
    public let codecName: String
    public let language: String?
    public let title: String?
    public let isDefault: Bool
}

// MARK: - MediaProbe Analyzer

public final class MediaProbe {
    
    public static func probe(url: URL) -> MediaProbeResult? {
        let pathStr = url.isFileURL ? url.path : url.absoluteString
        guard !pathStr.isEmpty else { return nil }
        
        var formatContext: UnsafeMutablePointer<AVFormatContext>? = avformat_alloc_context()
        guard avformat_open_input(&formatContext, pathStr, nil, nil) == 0, let ctx = formatContext else {
            return nil
        }
        defer {
            avformat_close_input(&formatContext)
        }
        
        guard avformat_find_stream_info(ctx, nil) >= 0 else {
            return nil
        }
        
        let containerName = String(cString: ctx.pointee.iformat.pointee.name)
        let durationSeconds = Double(ctx.pointee.duration) / Double(AV_TIME_BASE)
        
        var videoTracks: [ProbeVideoTrack] = []
        var audioTracks: [ProbeAudioTrack] = []
        var subtitleTracks: [ProbeSubtitleTrack] = []
        
        for i in 0..<Int(ctx.pointee.nb_streams) {
            guard let stream = ctx.pointee.streams[i]?.pointee else { continue }
            guard let codecpar = stream.codecpar?.pointee else { continue }
            
            let streamIndex = Int32(i)
            let codecId = codecpar.codec_id
            let codecName = String(cString: avcodec_get_name(codecId))
            
            let title = getMetadata(from: stream.metadata, key: "title")
            let language = getMetadata(from: stream.metadata, key: "language")
            let isDefault = (stream.disposition & AV_DISPOSITION_DEFAULT) != 0
            
            switch codecpar.codec_type {
            case AVMEDIA_TYPE_VIDEO:
                let width = codecpar.width
                let height = codecpar.height
                let fps = stream.r_frame_rate.den > 0 ? Double(stream.r_frame_rate.num) / Double(stream.r_frame_rate.den) : 0.0
                let bitDepth = codecpar.bits_per_raw_sample > 0 ? codecpar.bits_per_raw_sample : 8
                
                var isDoVi = false
                var doviProfile: UInt8? = nil
                var doviLevel: UInt8? = nil
                
                // Inspect side data for Dolby Vision configuration
                if let sideData = av_packet_side_data_get(codecpar.coded_side_data, codecpar.nb_coded_side_data, AV_PKT_DATA_DOVI_CONF) {
                    let doviConf = sideData.pointee.data.withMemoryRebound(to: AVDOVIDecoderConfigurationRecord.self, capacity: 1) { $0.pointee }
                    isDoVi = true
                    doviProfile = doviConf.dv_profile
                    doviLevel = doviConf.dv_level
                }
                
                videoTracks.append(ProbeVideoTrack(
                    index: streamIndex,
                    codecID: codecId,
                    codecName: codecName,
                    width: width,
                    height: height,
                    frameRate: fps,
                    bitDepth: bitDepth,
                    isDolbyVision: isDoVi,
                    doviProfile: doviProfile,
                    doviLevel: doviLevel
                ))
                
            case AVMEDIA_TYPE_AUDIO:
                let channels = codecpar.ch_layout.nb_channels
                let sampleRate = codecpar.sample_rate
                // Detect Atmos (E-AC-3 JOC or TrueHD Atmos)
                let isEac3 = (codecId == AV_CODEC_ID_EAC3)
                let isTrueHD = (codecId == AV_CODEC_ID_TRUEHD)
                let hasAtmosKeyword = (title?.localizedCaseInsensitiveContains("atmos") ?? false)
                let hasAtmos = (isEac3 && hasAtmosKeyword) || (isTrueHD && hasAtmosKeyword) || isEac3
                
                audioTracks.append(ProbeAudioTrack(
                    index: streamIndex,
                    codecID: codecId,
                    codecName: codecName,
                    language: language,
                    title: title,
                    channels: channels,
                    sampleRate: sampleRate,
                    isDefault: isDefault,
                    hasAtmos: hasAtmos
                ))
                
            case AVMEDIA_TYPE_SUBTITLE:
                subtitleTracks.append(ProbeSubtitleTrack(
                    index: streamIndex,
                    codecID: codecId,
                    codecName: codecName,
                    language: language,
                    title: title,
                    isDefault: isDefault
                ))
                
            default:
                break
            }
        }
        
        return MediaProbeResult(
            url: url,
            containerFormat: containerName,
            durationInSeconds: max(0, durationSeconds),
            videoTracks: videoTracks,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks
        )
    }
    
    private static func getMetadata(from dict: OpaquePointer?, key: String) -> String? {
        guard let dict = dict else { return nil }
        guard let entry = av_dict_get(dict, key, nil, 0) else { return nil }
        return String(cString: entry.pointee.value)
    }
}
