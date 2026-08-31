//
//  CloudMediaProxyServer.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation
import Network

/// A high-performance, lightweight local HTTP streaming proxy server.
/// Allows MobileVLCKit / AVPlayer to stream protected cloud media (Google Drive, etc.)
/// by forwarding authenticated HTTP headers, following redirects internally,
/// and supporting HTTP 206 Range requests for fast scrubbing and seeking.
public final class CloudMediaProxyServer {
    public static let shared = CloudMediaProxyServer()
    
    private struct RegisteredStream {
        let remoteURL: URL
        let headers: [String: String]
    }
    
    private var listener: NWListener?
    private var port: UInt16 = 8089
    private var registeredStreams: [String: RegisteredStream] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.swiftytorrent.mediaproxy", qos: .userInitiated)
    private var isStarted = false
    
    private init() {
        startServer(port: 8089)
    }
    
    // MARK: - Server Lifecycle
    
    public func startServer(port: UInt16 = 8089) {
        lock.lock()
        if isStarted && listener != nil {
            lock.unlock()
            return
        }
        lock.unlock()
        
        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.noDelay = true
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true
            
            let nwPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 8089)!
            let newListener = try NWListener(using: params, on: nwPort)
            
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let assignedPort = newListener.port?.rawValue {
                        self.lock.lock()
                        self.port = assignedPort
                        self.isStarted = true
                        self.lock.unlock()
                        print("[CloudMediaProxyServer] Listening on http://127.0.0.1:\(assignedPort)")
                    }
                case .failed(let error):
                    print("[CloudMediaProxyServer] Listener failed on port \(port): \(error), trying next port...")
                    self.lock.lock()
                    self.isStarted = false
                    self.listener = nil
                    self.lock.unlock()
                    if port < 8099 {
                        self.startServer(port: port + 1)
                    }
                default:
                    break
                }
            }
            
            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            newListener.start(queue: queue)
            
            lock.lock()
            self.listener = newListener
            self.port = port
            self.isStarted = true
            lock.unlock()
        } catch {
            print("[CloudMediaProxyServer] Failed to initialize listener on port \(port): \(error)")
            if port < 8099 {
                startServer(port: port + 1)
            }
        }
    }
    
    public func streamingURL(for streamId: String, remoteURL: URL, headers: [String: String]) -> URL {
        let safeKey = streamId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? streamId
        
        lock.lock()
        let regStream = RegisteredStream(remoteURL: remoteURL, headers: headers)
        registeredStreams[streamId] = regStream
        if safeKey != streamId {
            registeredStreams[safeKey] = regStream
        }
        let currentPort = self.port
        let started = self.isStarted
        lock.unlock()
        
        if !started {
            startServer(port: currentPort)
        }
        
        return URL(string: "http://127.0.0.1:\(currentPort)/stream/\(safeKey)") ?? URL(string: "http://127.0.0.1:\(currentPort)/stream")!
    }
    
    // MARK: - Connection Handling
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(connection: connection)
    }
    
    private func receiveHTTPRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, let requestString = String(data: data, encoding: .utf8) {
                self.processHTTPRequest(requestString, connection: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            }
        }
    }
    
    private func processHTTPRequest(_ requestString: String, connection: NWConnection) {
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendHTTPResponse(status: 400, message: "Bad Request", connection: connection)
            return
        }
        print("[CloudMediaProxyServer] Processing HTTP Request: \(requestLine)")
        
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
            sendHTTPResponse(status: 405, message: "Method Not Allowed", connection: connection)
            return
        }
        
        let path = parts[1]
        guard let rawId = path.components(separatedBy: "/stream/").last?.components(separatedBy: "?").first else {
            sendHTTPResponse(status: 404, message: "Not Found", connection: connection)
            return
        }
        
        let decodedId = rawId.removingPercentEncoding ?? rawId
        
        lock.lock()
        let stream = registeredStreams[rawId] ?? registeredStreams[decodedId]
        lock.unlock()
        
        guard let stream = stream else {
            print("[CloudMediaProxyServer] 404 Stream Not Found for id: '\(rawId)' (decoded: '\(decodedId)')")
            sendHTTPResponse(status: 404, message: "Stream Not Found", connection: connection)
            return
        }
        
        // Extract Range header if present
        var rangeHeader: String?
        for line in lines {
            if line.lowercased().hasPrefix("range:") {
                let rangeParts = line.components(separatedBy: ":")
                if rangeParts.count >= 2 {
                    rangeHeader = rangeParts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        print("[CloudMediaProxyServer] Proxying stream to: \(stream.remoteURL), range: \(rangeHeader ?? "none")")
        proxyRemoteStream(stream: stream, rangeHeader: rangeHeader, isHeadRequest: parts[0] == "HEAD", connection: connection)
    }
    
    // MARK: - Remote Proxying
    
    private func proxyRemoteStream(
        stream: RegisteredStream,
        rangeHeader: String?,
        isHeadRequest: Bool,
        connection: NWConnection
    ) {
        var request = URLRequest(url: stream.remoteURL)
        request.httpMethod = isHeadRequest ? "HEAD" : "GET"
        
        for (key, value) in stream.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let range = rangeHeader {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        
        let delegate = ProxySessionDelegate(connection: connection, isHeadRequest: isHeadRequest)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        delegate.attachTask(task)
        task.resume()
    }
    
    private func sendHTTPResponse(status: Int, message: String, connection: NWConnection) {
        let response = "HTTP/1.1 \(status) \(message)\r\nContent-Length: \(message.utf8.count)\r\nConnection: close\r\n\r\n\(message)"
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }
}

// MARK: - URLSession Proxy Delegate

private final class ProxySessionDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    private let connection: NWConnection
    private let isHeadRequest: Bool
    private var dataTask: URLSessionDataTask?
    private var hasSentHeaders = false
    private let lock = NSLock()
    private var isCancelled = false
    
    init(connection: NWConnection, isHeadRequest: Bool) {
        self.connection = connection
        self.isHeadRequest = isHeadRequest
        super.init()
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .cancelled, .failed:
                self.lock.lock()
                self.isCancelled = true
                let task = self.dataTask
                self.lock.unlock()
                task?.cancel()
            default:
                break
            }
        }
    }
    
    func attachTask(_ task: URLSessionDataTask) {
        lock.lock()
        self.dataTask = task
        let cancelled = self.isCancelled
        lock.unlock()
        if cancelled {
            task.cancel()
        }
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Follow redirect internally in URLSession without exposing redirect to VLC
        completionHandler(request)
    }
    
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        
        guard !cancelled, let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            connection.cancel()
            return
        }
        
        print("[CloudMediaProxyServer] Remote responded with HTTP status: \(httpResponse.statusCode)")
        
        // Don't send redirect headers to VLC; wait for final 200/206 response
        if (300...399).contains(httpResponse.statusCode) {
            completionHandler(.allow)
            return
        }
        
        var headerString = "HTTP/1.1 \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))\r\n"
        var hasAcceptRanges = false
        
        for (key, value) in httpResponse.allHeaderFields {
            let keyStr = "\(key)"
            let lower = keyStr.lowercased()
            if lower == "accept-ranges" {
                hasAcceptRanges = true
            }
            if lower != "transfer-encoding" && lower != "connection" {
                headerString += "\(keyStr): \(value)\r\n"
            }
        }
        if !hasAcceptRanges {
            headerString += "Accept-Ranges: bytes\r\n"
        }
        headerString += "Connection: close\r\n\r\n"
        
        if let headerData = headerString.data(using: .utf8) {
            connection.send(content: headerData, completion: .contentProcessed({ [weak self] error in
                if error != nil {
                    self?.lock.lock()
                    self?.isCancelled = true
                    self?.lock.unlock()
                    self?.dataTask?.cancel()
                }
            }))
            hasSentHeaders = true
        }
        
        if isHeadRequest {
            completionHandler(.cancel)
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ [weak self] _ in
                self?.connection.cancel()
            }))
        } else {
            completionHandler(.allow)
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        
        guard !cancelled else {
            dataTask.cancel()
            return
        }
        
        connection.send(content: data, completion: .contentProcessed({ [weak self] error in
            if error != nil {
                self?.lock.lock()
                self?.isCancelled = true
                self?.lock.unlock()
                self?.dataTask?.cancel()
            }
        }))
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        
        if !cancelled {
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ [weak self] _ in
                self?.connection.cancel()
            }))
        } else {
            connection.cancel()
        }
    }
}
