//
//  FFmpegRemuxer.swift
//  MediaKit
//
//  Zero-transcoding on-the-fly Fragmented MP4 (fMP4) Remuxer.
//  Extracts H.264/HEVC/DoVi and AAC/AC3/E-AC-3 streams into fMP4 segments.
//

import Foundation
import Libavformat
import Libavcodec
import Libavutil

public final class FFmpegRemuxer {
    
    private let sourceURL: URL
    private let queue = DispatchQueue(label: "com.mediakit.remuxer", qos: .userInitiated)
    
    public let durationInSeconds: Double
    public let targetSegmentDuration: Double = 4.0
    public var totalSegments: Int {
        guard durationInSeconds > 0 else { return 1 }
        return max(1, Int(ceil(durationInSeconds / targetSegmentDuration)))
    }
    
    private var cachedInitSegment: Data?
    private var segmentCache = [Int: Data]()
    private let cacheLock = NSLock()
    
    public init?(url: URL) {
        self.sourceURL = url
        
        var formatCtx: UnsafeMutablePointer<AVFormatContext>? = avformat_alloc_context()
        let pathStr = url.isFileURL ? url.path : url.absoluteString
        guard avformat_open_input(&formatCtx, pathStr, nil, nil) == 0, let ctx = formatCtx else {
            return nil
        }
        guard avformat_find_stream_info(ctx, nil) >= 0 else {
            avformat_close_input(&formatCtx)
            return nil
        }
        
        let dur = Double(ctx.pointee.duration) / Double(AV_TIME_BASE)
        self.durationInSeconds = max(0, dur)
        avformat_close_input(&formatCtx)
    }
    
    // MARK: - Init Segment (ftyp + moov)
    
    /// Generates the fMP4 initialization segment (ftyp + moov boxes)
    public func getInitSegment() -> Data? {
        return queue.sync {
            if let cached = cachedInitSegment {
                return cached
            }
            guard let data = buildInitSegment() else { return nil }
            self.cachedInitSegment = data
            return data
        }
    }
    
    // MARK: - Media Segment (moof + mdat)
    
    /// Generates media segment N for the requested target duration interval with ring-buffer caching
    public func getSegment(index: Int) -> Data? {
        cacheLock.lock()
        if let cached = segmentCache[index] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        return queue.sync {
            cacheLock.lock()
            if let cached = segmentCache[index] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()
            
            guard let data = buildSegment(index: index) else { return nil }
            
            cacheLock.lock()
            segmentCache[index] = data
            // Keep at most 16 segments in RAM (~30MB)
            if segmentCache.count > 16 {
                let sortedKeys = segmentCache.keys.sorted()
                let toRemove = sortedKeys.prefix(segmentCache.count - 16)
                for key in toRemove {
                    segmentCache.removeValue(forKey: key)
                }
            }
            cacheLock.unlock()
            return data
        }
    }
    
    // MARK: - Internal Remuxing Implementation
    
    private class BufferWriter {
        var data = Data()
    }
    
    private func buildInitSegment() -> Data? {
        var inCtx: UnsafeMutablePointer<AVFormatContext>? = avformat_alloc_context()
        let pathStr = sourceURL.isFileURL ? sourceURL.path : sourceURL.absoluteString
        guard avformat_open_input(&inCtx, pathStr, nil, nil) == 0, let input = inCtx else {
            return nil
        }
        defer { avformat_close_input(&inCtx) }
        guard avformat_find_stream_info(input, nil) >= 0 else { return nil }
        
        var outCtx: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_alloc_output_context2(&outCtx, nil, "mp4", nil) == 0, let output = outCtx else {
            return nil
        }
        defer { avformat_free_context(output) }
        
        // Map streams: First video and compatible audio
        var streamMapping = [Int: Int]()
        var outStreamIdx = 0
        
        for i in 0..<Int(input.pointee.nb_streams) {
            guard let inStream = input.pointee.streams[i]?.pointee else { continue }
            guard let inCodecPar = inStream.codecpar?.pointee else { continue }
            
            if inCodecPar.codec_type == AVMEDIA_TYPE_VIDEO && streamMapping.values.filter({ $0 == 0 }).isEmpty {
                guard let outStream = avformat_new_stream(output, nil) else { continue }
                avcodec_parameters_copy(outStream.pointee.codecpar, inStream.codecpar)
                outStream.pointee.codecpar?.pointee.codec_tag = 0
                streamMapping[i] = outStreamIdx
                outStreamIdx += 1
            } else if inCodecPar.codec_type == AVMEDIA_TYPE_AUDIO {
                // Only map AAC, AC3, EAC3
                if inCodecPar.codec_id == AV_CODEC_ID_AAC ||
                    inCodecPar.codec_id == AV_CODEC_ID_AC3 ||
                    inCodecPar.codec_id == AV_CODEC_ID_EAC3 {
                    guard let outStream = avformat_new_stream(output, nil) else { continue }
                    avcodec_parameters_copy(outStream.pointee.codecpar, inStream.codecpar)
                    outStream.pointee.codecpar?.pointee.codec_tag = 0
                    streamMapping[i] = outStreamIdx
                    outStreamIdx += 1
                    break // Map primary compatible audio stream
                }
            }
        }
        
        guard outStreamIdx > 0 else { return nil }
        
        let writer = BufferWriter()
        let opaquePtr = Unmanaged.passUnretained(writer).toOpaque()
        let bufferSize = 64 * 1024
        guard let avioBuffer = av_malloc(bufferSize) else { return nil }
        
        let writePacket: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32 = { opaque, buf, size in
            guard let opaque = opaque, let buf = buf, size > 0 else { return 0 }
            let writerObj = Unmanaged<BufferWriter>.fromOpaque(opaque).takeUnretainedValue()
            writerObj.data.append(buf, count: Int(size))
            return size
        }
        
        let avioCtx = avio_alloc_context(
            avioBuffer.assumingMemoryBound(to: UInt8.self),
            Int32(bufferSize),
            1,
            opaquePtr,
            nil,
            writePacket,
            nil
        )
        output.pointee.pb = avioCtx
        defer {
            av_freep(&output.pointee.pb)
        }
        
        // HLS fragmented MP4 flags
        av_opt_set(output.pointee.priv_data, "movflags", "empty_moov+default_base_moof+frag_keyframe+omit_tfhd_offset", 0)
        
        var dict: OpaquePointer?
        if avformat_write_header(output, &dict) < 0 {
            return nil
        }
        av_dict_free(&dict)
        
        // Flush buffer
        avio_flush(output.pointee.pb)
        return writer.data
    }
    
    private func buildSegment(index: Int) -> Data? {
        var inCtx: UnsafeMutablePointer<AVFormatContext>? = avformat_alloc_context()
        let pathStr = sourceURL.isFileURL ? sourceURL.path : sourceURL.absoluteString
        guard avformat_open_input(&inCtx, pathStr, nil, nil) == 0, let input = inCtx else {
            return nil
        }
        defer { avformat_close_input(&inCtx) }
        guard avformat_find_stream_info(input, nil) >= 0 else { return nil }
        
        var outCtx: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_alloc_output_context2(&outCtx, nil, "mp4", nil) == 0, let output = outCtx else {
            return nil
        }
        defer { avformat_free_context(output) }
        
        var streamMapping = [Int: Int]()
        var outStreamIdx = 0
        var primaryVideoStreamIdx: Int?
        
        for i in 0..<Int(input.pointee.nb_streams) {
            guard let inStream = input.pointee.streams[i]?.pointee else { continue }
            guard let inCodecPar = inStream.codecpar?.pointee else { continue }
            
            if inCodecPar.codec_type == AVMEDIA_TYPE_VIDEO && primaryVideoStreamIdx == nil {
                guard let outStream = avformat_new_stream(output, nil) else { continue }
                avcodec_parameters_copy(outStream.pointee.codecpar, inStream.codecpar)
                outStream.pointee.codecpar?.pointee.codec_tag = 0
                streamMapping[i] = outStreamIdx
                primaryVideoStreamIdx = i
                outStreamIdx += 1
            } else if inCodecPar.codec_type == AVMEDIA_TYPE_AUDIO {
                if inCodecPar.codec_id == AV_CODEC_ID_AAC ||
                    inCodecPar.codec_id == AV_CODEC_ID_AC3 ||
                    inCodecPar.codec_id == AV_CODEC_ID_EAC3 {
                    guard let outStream = avformat_new_stream(output, nil) else { continue }
                    avcodec_parameters_copy(outStream.pointee.codecpar, inStream.codecpar)
                    outStream.pointee.codecpar?.pointee.codec_tag = 0
                    streamMapping[i] = outStreamIdx
                    outStreamIdx += 1
                    break
                }
            }
        }
        
        guard let videoIdx = primaryVideoStreamIdx else { return nil }
        
        let writer = BufferWriter()
        let opaquePtr = Unmanaged.passUnretained(writer).toOpaque()
        let bufferSize = 128 * 1024
        guard let avioBuffer = av_malloc(bufferSize) else { return nil }
        
        let writePacket: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32 = { opaque, buf, size in
            guard let opaque = opaque, let buf = buf, size > 0 else { return 0 }
            let writerObj = Unmanaged<BufferWriter>.fromOpaque(opaque).takeUnretainedValue()
            writerObj.data.append(buf, count: Int(size))
            return size
        }
        
        let avioCtx = avio_alloc_context(
            avioBuffer.assumingMemoryBound(to: UInt8.self),
            Int32(bufferSize),
            1,
            opaquePtr,
            nil,
            writePacket,
            nil
        )
        output.pointee.pb = avioCtx
        defer {
            av_freep(&output.pointee.pb)
        }
        
        av_opt_set(output.pointee.priv_data, "movflags", "empty_moov+default_base_moof+frag_custom+omit_tfhd_offset", 0)
        
        var dict: OpaquePointer?
        if avformat_write_header(output, &dict) < 0 {
            return nil
        }
        av_dict_free(&dict)
        
        // Discard header data for media segment (init segment is served via init.mp4)
        writer.data.removeAll(keepingCapacity: true)
        
        // Seek to target segment start time
        let startTimeSec = Double(index) * targetSegmentDuration
        let endTimeSec = startTimeSec + targetSegmentDuration
        
        if index > 0 {
            let seekTimestamp = Int64(startTimeSec * Double(AV_TIME_BASE))
            av_seek_frame(input, -1, seekTimestamp, AVSEEK_FLAG_BACKWARD)
        }
        
        var packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        defer { av_packet_free(&packet) }
        guard let pkt = packet else { return nil }
        
        var packetsWritten = 0
        var firstVideoKeyframeSeen = (index == 0)
        
        while av_read_frame(input, pkt) >= 0 {
            let inStreamIdx = Int(pkt.pointee.stream_index)
            guard let outIdx = streamMapping[inStreamIdx] else {
                av_packet_unref(pkt)
                continue
            }
            
            guard let inStream = input.pointee.streams[inStreamIdx]?.pointee,
                  let outStream = output.pointee.streams[outIdx]?.pointee else {
                av_packet_unref(pkt)
                continue
            }
            
            let isKeyframe = (pkt.pointee.flags & AV_PKT_FLAG_KEY) != 0
            
            if inStreamIdx == videoIdx {
                if !firstVideoKeyframeSeen {
                    if !isKeyframe {
                        av_packet_unref(pkt)
                        continue
                    }
                    firstVideoKeyframeSeen = true
                }
                
                let ptsTime = Double(pkt.pointee.pts) * Double(inStream.time_base.num) / Double(inStream.time_base.den)
                if ptsTime >= endTimeSec && isKeyframe && packetsWritten > 0 {
                    av_packet_unref(pkt)
                    break
                }
            } else if !firstVideoKeyframeSeen {
                // Drop audio before the first video keyframe to maintain A/V sync
                av_packet_unref(pkt)
                continue
            }
            
            // Rescale timestamps to output timebase
            pkt.pointee.stream_index = Int32(outIdx)
            av_packet_rescale_ts(pkt, inStream.time_base, outStream.time_base)
            pkt.pointee.pos = -1
            
            if av_interleaved_write_frame(output, pkt) >= 0 {
                packetsWritten += 1
            }
            av_packet_unref(pkt)
        }
        
        guard packetsWritten > 0 else { return nil }
        
        // Flush the fragment cleanly (moof + mdat) into writer.data without writing any trailer or mfra!
        av_write_frame(output, nil)
        avio_flush(output.pointee.pb)
        
        return writer.data.isEmpty ? nil : writer.data
    }
}
