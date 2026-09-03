//
//  LocalHLSServer.swift
//  MediaKit
//
//  Ultra-lightweight embedded HTTP server running on 127.0.0.1 using Apple's Network.framework.
//  Serves on-demand HLS master playlists and fMP4 segments to native AVPlayer.
//

import Foundation
import Network

public final class LocalHLSServer {
    
    private let remuxer: FFmpegRemuxer
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.mediakit.hls.server", qos: .userInitiated)
    private var activeConnections = [ObjectIdentifier: NWConnection]()
    
    public private(set) var port: UInt16 = 0
    public private(set) var isRunning = false
    
    public init(remuxer: FFmpegRemuxer) {
        self.remuxer = remuxer
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Lifecycle
    
    /// Starts the local HTTP loopback server and returns the local master.m3u8 URL
    public func start() throws -> URL {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener
        
        let semaphore = DispatchSemaphore(value: 0)
        var startError: Error?
        
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let assignedPort = listener.port?.rawValue {
                    self?.port = assignedPort
                    self?.isRunning = true
                    print("[LocalHLSServer] Ready on http://127.0.0.1:\(assignedPort)")
                }
                semaphore.signal()
            case .failed(let error):
                print("[LocalHLSServer] Failed to start: \(error)")
                startError = error
                semaphore.signal()
            default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] newConnection in
            self?.handleNewConnection(newConnection)
        }
        
        listener.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 3.0)
        
        if let error = startError {
            throw error
        }
        guard port > 0 else {
            throw NSError(domain: "com.mediakit.hlsserver", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to bind local loopback port"])
        }
        
        return URL(string: "http://127.0.0.1:\(port)/master.m3u8")!
    }
    
    public func stop() {
        queue.sync {
            guard isRunning else { return }
            isRunning = false
            listener?.cancel()
            listener = nil
            for conn in activeConnections.values {
                conn.cancel()
            }
            activeConnections.removeAll()
            print("[LocalHLSServer] Stopped")
        }
    }
    
    // MARK: - Connection Handling
    
    private func handleNewConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        activeConnections[id] = connection
        
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .cancelled, .failed:
                if let conn = connection {
                    self?.activeConnections.removeValue(forKey: ObjectIdentifier(conn))
                }
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        receiveNextRequest(on: connection)
    }
    
    private func receiveNextRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] content, _, isComplete, error in
            guard let self = self, let connection = connection else { return }
            
            if let data = content, !data.isEmpty, let requestString = String(data: data, encoding: .utf8) {
                self.processHTTPRequest(requestString, connection: connection)
            }
            
            if isComplete || error != nil {
                self.activeConnections.removeValue(forKey: ObjectIdentifier(connection))
                connection.cancel()
            } else {
                self.receiveNextRequest(on: connection)
            }
        }
    }
    
    // MARK: - Request Routing
    
    private func processHTTPRequest(_ request: String, connection: NWConnection) {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            sendResponse(connection: connection, status: 400, contentType: "text/plain", body: Data())
            return
        }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, contentType: "text/plain", body: Data())
            return
        }
        
        let isHead = (parts[0].uppercased() == "HEAD")
        let path = parts[1].components(separatedBy: "?").first ?? parts[1]
        
        if path == "/master.m3u8" {
            let playlist = generateHLSPlaylist()
            let data = playlist.data(using: .utf8) ?? Data()
            sendResponse(connection: connection, status: 200, contentType: "application/x-mpegURL", body: data, isHead: isHead)
            
        } else if path == "/init.mp4" {
            if let initData = remuxer.getInitSegment() {
                sendResponse(connection: connection, status: 200, contentType: "video/mp4", body: initData, isHead: isHead)
            } else {
                sendResponse(connection: connection, status: 500, contentType: "text/plain", body: Data(), isHead: isHead)
            }
            
        } else if path.hasPrefix("/segment_") && path.hasSuffix(".m4s") {
            let indexStr = path.replacingOccurrences(of: "/segment_", with: "").replacingOccurrences(of: ".m4s", with: "")
            if let idx = Int(indexStr), let segData = remuxer.getSegment(index: idx) {
                sendResponse(connection: connection, status: 200, contentType: "video/iso.segment", body: segData, isHead: isHead)
            } else {
                sendResponse(connection: connection, status: 404, contentType: "text/plain", body: Data(), isHead: isHead)
            }
            
        } else {
            sendResponse(connection: connection, status: 404, contentType: "text/plain", body: Data(), isHead: isHead)
        }
    }
    
    private func sendResponse(connection: NWConnection, status: Int, contentType: String, body: Data, isHead: Bool = false) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Internal Server Error"
        }
        
        var header = "HTTP/1.1 \(status) \(statusText)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: keep-alive\r\n\r\n"
        
        var responseData = header.data(using: .utf8) ?? Data()
        if !isHead {
            responseData.append(body)
        }
        
        connection.send(content: responseData, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed({ _ in
            // Keep connection alive for AVPlayer pipelining
        }))
    }
    
    // MARK: - Playlist Generator
    
    private func generateHLSPlaylist() -> String {
        let segDuration = remuxer.targetSegmentDuration
        let totalCount = remuxer.totalSegments
        let totalDuration = remuxer.durationInSeconds
        
        var m3u8 = "#EXTM3U\n"
        m3u8 += "#EXT-X-VERSION:7\n"
        m3u8 += "#EXT-X-TARGETDURATION:\(Int(ceil(segDuration)))\n"
        m3u8 += "#EXT-X-MEDIA-SEQUENCE:0\n"
        m3u8 += "#EXT-X-PLAYLIST-TYPE:VOD\n"
        m3u8 += "#EXT-X-INDEPENDENT-SEGMENTS\n"
        m3u8 += "#EXT-X-MAP:URI=\"init.mp4\"\n"
        
        for i in 0..<totalCount {
            let dur: Double
            if i == totalCount - 1 && totalDuration > 0 {
                dur = max(0.1, totalDuration - (Double(i) * segDuration))
            } else {
                dur = segDuration
            }
            m3u8 += "#EXTINF:\(String(format: "%.3f", dur)),\n"
            m3u8 += "segment_\(i).m4s\n"
        }
        m3u8 += "#EXT-X-ENDLIST\n"
        return m3u8
    }
}
