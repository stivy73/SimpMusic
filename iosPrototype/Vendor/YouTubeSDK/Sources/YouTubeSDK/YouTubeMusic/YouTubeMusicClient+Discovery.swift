//
//  YouTubeMusicClient+Discovery.swift
//  YouTubeSDK
//
//  Created by Aarav Gupta on 13/03/26.
//

import Foundation

extension YouTubeMusicClient {
    
    public func getHome() async throws -> [YouTubeMusicSection] {
        let page = try await getHomePage()
        return page.sections
    }

    public func getHomePage(regionCode: String? = nil, languageCode: String? = nil) async throws -> YouTubeMusicHomePage {
        let client = makeNetwork(regionCode: regionCode, languageCode: languageCode)
        let body = ["browseId": YouTubeSDKConstants.InternalKeys.BrowseIDs.Music.home]
        let data = try await client.get("browse", body: body)
        return parseHomePage(from: data)
    }

    public func getHomeContinuation(
        token: String,
        regionCode: String? = nil,
        languageCode: String? = nil
    ) async throws -> YouTubeMusicHomePage {
        let client = makeNetwork(regionCode: regionCode, languageCode: languageCode)
        let data = try await client.get("browse", body: ["continuation": token])
        return parseHomePage(from: data)
    }
    
    public func getCharts() async throws -> [YouTubeMusicSection] {
        return try await browseSection(browseId: YouTubeSDKConstants.InternalKeys.BrowseIDs.Music.charts)
    }
    
    public func getNewReleases() async throws -> [YouTubeMusicSection] {
        return try await browseSection(browseId: YouTubeSDKConstants.InternalKeys.BrowseIDs.Music.newReleases)
    }
    
    public func getMoods() async throws -> [YouTubeMusicSection] {
        return try await browseSection(browseId: YouTubeSDKConstants.InternalKeys.BrowseIDs.Music.moods)
    }
    
    // MARK: - User Library
        
    public func getLikedSongs() async throws -> [YouTubeMusicSong] {
        let data = try await network.get("browse", body: ["browseId": YouTubeSDKConstants.InternalKeys.BrowseIDs.Music.likedVideos])
        return await parseMusicItems(from: data)
    }
    
    public func getHistory() async throws -> [YouTubeMusicSong] {
        let data = try await network.get("browse", body: ["browseId": YouTubeSDKConstants.InternalKeys.BrowseIDs.Music.history])
        return await parseMusicItems(from: data)
    }
    
    public func getLibrary() async throws -> [YouTubeMusicSection] {
        let data = try await network.get("browse", body: ["browseId": YouTubeSDKConstants.InternalKeys.BrowseIDs.Music.library])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return await parseSections(from: json)
    }
    
    private func browseSection(browseId: String) async throws -> [YouTubeMusicSection] {
        let body = ["browseId": browseId]
        let data = try await network.get("browse", body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return await parseSections(from: json)
    }

    private func makeNetwork(regionCode: String?, languageCode: String?) -> NetworkClient {
        guard let normalizedRegion = normalizedRegionCode(regionCode) else {
            return network
        }

        let normalizedLanguage = normalizedLanguageCode(languageCode)
        let context = InnerTubeContext(
            client: ClientConfig.webRemix,
            cookies: cookies,
            gl: normalizedRegion,
            hl: normalizedLanguage
        )
        return NetworkClient(context: context, baseURL: YouTubeSDKConstants.URLS.API.youtubeMusicInnerTubeURL)
    }

    private func normalizedRegionCode(_ rawRegionCode: String?) -> String? {
        guard let raw = rawRegionCode?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let uppercased = raw.uppercased()
        guard uppercased.count == 2 else { return nil }
        return uppercased
    }

    private func normalizedLanguageCode(_ rawLanguageCode: String?) -> String {
        guard let raw = rawLanguageCode?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "en"
        }

        if let separator = raw.firstIndex(where: { $0 == "-" || $0 == "_" }) {
            return String(raw[..<separator]).lowercased()
        }

        return raw.lowercased()
    }
}
