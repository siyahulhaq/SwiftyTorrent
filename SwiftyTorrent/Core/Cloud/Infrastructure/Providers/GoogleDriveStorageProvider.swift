//
//  GoogleDriveStorageProvider.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Foundation
#if !os(tvOS)
import AuthenticationServices
#endif

public final class GoogleDriveStorageProvider: NSObject, CloudStorageProviderProtocol {
    public static let providerId = "google_drive"
    
    // Standard Google Drive OAuth2 endpoints
    public static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let defaultClientId = "872412351720-default.apps.googleusercontent.com" // Configurable via customProperties
    public static let scopes = [
        "https://www.googleapis.com/auth/drive.readonly",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile"
    ]
    
    public var descriptor: CloudProviderDescriptor {
        CloudProviderDescriptor(
            id: Self.providerId,
            displayName: "Google Drive",
            subtitle: "Google Cloud Storage",
            iconName: "externaldrive.badge.icloud",
            brandColorHex: "34A853",
            authType: .oauth2(
                authURL: Self.authEndpoint,
                tokenURL: Self.tokenEndpoint,
                clientId: Self.defaultClientId,
                scopes: Self.scopes
            ),
            capabilities: [.streaming, .downloading, .search, .deletion]
        )
    }
    
    public var account: CloudAccount?
    #if !os(tvOS)
    private weak var presentationAnchor: ASPresentationAnchor?
    #endif
    
    public init(account: CloudAccount? = nil) {
        self.account = account
    }
    
    // MARK: - Authentication
    
    #if os(tvOS)
    @MainActor
    public func authenticate(from presentingVC: PlatformViewController?) async throws -> CloudAccount {
        throw NSError(domain: "GoogleDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Google Drive OAuth web login is not supported on Apple TV. Please sign in on iOS or Mac."])
    }
    
    @MainActor
    public func authenticate(clientId: String, clientSecret: String? = nil, from presentingVC: PlatformViewController?) async throws -> CloudAccount {
        throw NSError(domain: "GoogleDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Google Drive OAuth web login is not supported on Apple TV. Please sign in on iOS or Mac."])
    }
    #else
    @MainActor
    public func authenticate(from presentingVC: PlatformViewController?) async throws -> CloudAccount {
        let configuredClientId = UserDefaults.standard.string(forKey: "google_drive_client_id") ?? account?.customProperties["clientId"] ?? Self.defaultClientId
        let configuredClientSecret = UserDefaults.standard.string(forKey: "google_drive_client_secret") ?? account?.customProperties["clientSecret"]
        return try await authenticate(clientId: configuredClientId, clientSecret: configuredClientSecret, from: presentingVC)
    }
    
    @MainActor
    public func authenticate(clientId: String, clientSecret: String? = nil, from presentingVC: PlatformViewController?) async throws -> CloudAccount {
        let cleanClientId = clientId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        let callbackScheme = "com.googleusercontent.apps.\(cleanClientId)"
        let redirectURI = "\(callbackScheme):/oauth2redirect"
        let scopeString = Self.scopes.joined(separator: " ")
        
        guard var components = URLComponents(url: Self.authEndpoint, resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "GoogleDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth URL"])
        }
        
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopeString),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let authURL = components.url else {
            throw NSError(domain: "GoogleDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to construct OAuth URL"])
        }
        
        #if canImport(UIKit)
        self.presentationAnchor = presentingVC?.view.window ?? UIApplication.shared.windows.first
        #elseif canImport(AppKit)
        self.presentationAnchor = presentingVC?.view.window ?? NSApplication.shared.windows.first
        #endif
        
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: NSError(domain: "GoogleDrive", code: 401, userInfo: [NSLocalizedDescriptionKey: "OAuth cancelled"]))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
        
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw NSError(domain: "GoogleDrive", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authorization code not found in redirect"])
        }
        
        // Exchange code for tokens
        return try await exchangeCodeForTokens(code: code, clientId: clientId, clientSecret: clientSecret, redirectURI: redirectURI)
    }
    #endif
    
    public func authenticateWithToken(accessToken: String, refreshToken: String? = nil) async throws -> CloudAccount {
        let userProfile = try? await fetchUserProfile(accessToken: accessToken)
        let email = userProfile?["email"] as? String ?? "Google Drive Account"
        let name = userProfile?["name"] as? String ?? email
        
        let newAccount = CloudAccount(
            providerId: Self.providerId,
            accountName: email,
            displayName: name,
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenExpiryDate: Date().addingTimeInterval(3600 * 24 * 30),
            customProperties: [:]
        )
        
        CloudAccountManager.shared.save(account: newAccount)
        self.account = newAccount
        return newAccount
    }
    
    private func exchangeCodeForTokens(code: String, clientId: String, clientSecret: String?, redirectURI: String) async throws -> CloudAccount {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyParams = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        if let clientSecret = clientSecret, !clientSecret.isEmpty {
            bodyParams["client_secret"] = clientSecret
        }
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GoogleDrive", code: 401, userInfo: [NSLocalizedDescriptionKey: "Failed to exchange authorization code"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw NSError(domain: "GoogleDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid token response format"])
        }
        
        let refreshToken = json["refresh_token"] as? String
        let expiresIn = json["expires_in"] as? Double ?? 3600
        let expiryDate = Date().addingTimeInterval(expiresIn)
        
        // Fetch user profile info
        let userProfile = try? await fetchUserProfile(accessToken: accessToken)
        let email = userProfile?["email"] as? String ?? "Google Drive Account"
        let name = userProfile?["name"] as? String ?? email
        
        let newAccount = CloudAccount(
            providerId: Self.providerId,
            accountName: email,
            displayName: name,
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenExpiryDate: expiryDate,
            customProperties: ["clientId": clientId]
        )
        
        CloudAccountManager.shared.save(account: newAccount)
        self.account = newAccount
        return newAccount
    }
    
    private func fetchUserProfile(accessToken: String) async throws -> [String: Any]? {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    
    public func disconnect() async throws {
        if let account = self.account {
            CloudAccountManager.shared.delete(account: account)
            self.account = nil
        }
    }
    
    // MARK: - Token Refresh
    
    private func getValidAccessToken() async throws -> String {
        guard let account = self.account, let token = account.accessToken else {
            throw NSError(domain: "GoogleDrive", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please sign in to Google Drive."])
        }
        
        // If token has not expired, return it
        if let expiry = account.tokenExpiryDate, expiry > Date().addingTimeInterval(60) {
            return token
        }
        
        // If expired and refresh token is available, refresh it
        if let refreshToken = account.refreshToken {
            do {
                let clientId = account.customProperties["clientId"] ?? UserDefaults.standard.string(forKey: "google_drive_client_id") ?? Self.defaultClientId
                let clientSecret = UserDefaults.standard.string(forKey: "google_drive_client_secret")
                
                var request = URLRequest(url: Self.tokenEndpoint)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                
                var bodyParams = [
                    "refresh_token": refreshToken,
                    "client_id": clientId,
                    "grant_type": "refresh_token"
                ]
                if let clientSecret = clientSecret, !clientSecret.isEmpty {
                    bodyParams["client_secret"] = clientSecret
                }
                
                request.httpBody = bodyParams
                    .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
                    .joined(separator: "&")
                    .data(using: .utf8)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let newAccessToken = json["access_token"] as? String {
                    let expiresIn = json["expires_in"] as? Double ?? 3600
                    let updatedAccount = CloudAccount(
                        id: account.id,
                        providerId: account.providerId,
                        accountName: account.accountName,
                        displayName: account.displayName,
                        accessToken: newAccessToken,
                        refreshToken: (json["refresh_token"] as? String) ?? refreshToken,
                        tokenExpiryDate: Date().addingTimeInterval(expiresIn),
                        customProperties: account.customProperties
                    )
                    CloudAccountManager.shared.save(account: updatedAccount)
                    self.account = updatedAccount
                    return newAccessToken
                }
            } catch {
                print("Failed to refresh token: \(error)")
            }
        }
        
        return token
    }
    
    private func parseGoogleError(from data: Data, response: URLResponse?, fallback: String) -> NSError {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorDict = json["error"] as? [String: Any],
           let message = errorDict["message"] as? String {
            return NSError(domain: "GoogleDrive", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Google Drive (\(statusCode)): \(message)"])
        } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return NSError(domain: "GoogleDrive", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Google Drive (\(statusCode)): \(text)"])
        }
        return NSError(domain: "GoogleDrive", code: statusCode, userInfo: [NSLocalizedDescriptionKey: fallback])
    }

    // MARK: - File Browsing
    
    public func listFolder(folderId: String?, cursor: String?) async throws -> CloudFolderContents {
        let token = try await getValidAccessToken()
        
        let parentId = folderId ?? "root"
        let query = "'\(parentId)' in parents and trashed = false"
        
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,size,createdTime,modifiedTime)"),
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "orderBy", value: "folder,name"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
            URLQueryItem(name: "spaces", value: "drive")
        ]
        
        if let cursor = cursor {
            components.queryItems?.append(URLQueryItem(name: "pageToken", value: cursor))
        }
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw parseGoogleError(from: data, response: response, fallback: "Failed to list folder contents")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filesJson = json["files"] as? [[String: Any]] else {
            return CloudFolderContents(items: [])
        }
        
        let dateFormatter = ISO8601DateFormatter()
        let items: [CloudFileItem] = filesJson.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String,
                  let mimeType = dict["mimeType"] as? String else { return nil }
            
            let isFolder = (mimeType == "application/vnd.google-apps.folder")
            let size = UInt64(dict["size"] as? String ?? "0") ?? 0
            let createdStr = dict["createdTime"] as? String
            let modifiedStr = dict["modifiedTime"] as? String
            let headers = ["Authorization": "Bearer \(token)"]
            
            let streamURL = CloudMediaProxyServer.shared.streamingURL(
                for: id,
                remoteURL: URL(string: "https://www.googleapis.com/drive/v3/files/\(id)?alt=media")!,
                headers: headers
            )
            
            return CloudFileItem(
                id: id,
                providerId: Self.providerId,
                accountId: account?.id,
                name: name,
                path: id,
                size: size,
                isDirectory: isFolder,
                mimeType: mimeType,
                localURL: nil,
                remoteURL: streamURL,
                streamHeaders: headers,
                isDownloads: false,
                createdAt: createdStr.flatMap { dateFormatter.date(from: $0) },
                modifiedAt: modifiedStr.flatMap { dateFormatter.date(from: $0) }
            )
        }
        
        let nextToken = json["nextPageToken"] as? String
        return CloudFolderContents(items: items, nextCursor: nextToken)
    }
    
    // MARK: - Streaming & Download
    
    public func getStreamURL(for item: CloudFileItem) async throws -> URL {
        print("[GoogleDriveStorageProvider] getStreamURL for '\(item.name)', id='\(item.id)'")
        if let localURL = item.localURL {
            print("[GoogleDriveStorageProvider] Returning existing localURL: \(localURL)")
            return localURL
        }
        let token = try await getValidAccessToken()
        print("[GoogleDriveStorageProvider] Got access token (len=\(token.count))")
        let remoteURL = URL(string: "https://www.googleapis.com/drive/v3/files/\(item.id)?alt=media")!
        let headers = ["Authorization": "Bearer \(token)"]
        let streamURL = CloudMediaProxyServer.shared.streamingURL(for: item.id, remoteURL: remoteURL, headers: headers)
        print("[GoogleDriveStorageProvider] Created streamURL: \(streamURL)")
        return streamURL
    }
    
    public func download(item: CloudFileItem, progress: @escaping (Double) -> Void) async throws -> URL {
        print("[GoogleDriveStorageProvider] download started for '\(item.name)', id='\(item.id)'")
        let token = try await getValidAccessToken()
        
        let url: URL
        let fileName: String
        if let mime = item.mimeType, mime.hasPrefix("application/vnd.google-apps.") {
            // Google Docs / Sheets / Slides cannot be downloaded via alt=media, must be exported as PDF
            url = URL(string: "https://www.googleapis.com/drive/v3/files/\(item.id)/export?mimeType=application/pdf")!
            fileName = item.name.hasSuffix(".pdf") ? item.name : "\(item.name).pdf"
        } else {
            url = URL(string: "https://www.googleapis.com/drive/v3/files/\(item.id)?alt=media")!
            fileName = item.name
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("[GoogleDriveStorageProvider] Downloading from URL: \(url)...")
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            print("[GoogleDriveStorageProvider] Download failed with HTTP \(code)")
            throw NSError(domain: "GoogleDrive", code: code, userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(code))"])
        }
        
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let destURL = cachesDir.appendingPathComponent("\(item.id)_\(fileName)")
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        
        print("[GoogleDriveStorageProvider] Successfully saved download to: \(destURL)")
        progress(1.0)
        return destURL
    }
    
    public func delete(item: CloudFileItem) async throws {
        let token = try await getValidAccessToken()
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(item.id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw parseGoogleError(from: data, response: response, fallback: "Delete failed")
        }
    }
    
}

#if !os(tvOS)
// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleDriveStorageProvider: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return presentationAnchor ?? ASPresentationAnchor()
    }
}
#endif
