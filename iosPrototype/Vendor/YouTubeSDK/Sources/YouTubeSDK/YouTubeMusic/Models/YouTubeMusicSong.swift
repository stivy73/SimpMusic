//
//  YouTubeMusicSong.swift
//  YouTubeSDK
//
//  Created by Aarav Gupta on 26/12/25.
//

import Foundation

public struct YouTubeMusicSong: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let artists: [String]
    public let album: String?
    public let duration: TimeInterval?
    public let thumbnailURL: URL?
    public let videoId: String
    public let isExplicit: Bool
    
    // Helper for UI
    public var artistsDisplay: String { artists.joined(separator: ", ") }

    /// Robust Manual Initializer.
    /// Extracts data from a "musicResponsiveListItemRenderer" dictionary.
    init?(from data: [String: Any]) {
        // 1. ID Extraction (Try videoId, fallback to navigationEndpoint)
        var extractedId: String?
        
        if let vid = data["videoId"] as? String {
            extractedId = vid
        } else if let playlistItem = data["playlistItemData"] as? [String: Any],
                  let vid = playlistItem["videoId"] as? String {
            extractedId = vid
        } else if let endpoint = data["navigationEndpoint"] as? [String: Any],
                  let watch = endpoint["watchEndpoint"] as? [String: Any],
                  let vid = watch["videoId"] as? String {
            extractedId = vid
        }
        
        guard let finalId = extractedId else { return nil }
        self.id = finalId
        self.videoId = finalId
        
        // 2. Title (Flex Column 0)
        if let columns = data["flexColumns"] as? [[String: Any]],
           let firstCol = columns.first,
           let textParams = firstCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
           let textData = textParams["text"] as? [String: Any],
           let runs = textData["runs"] as? [[String: Any]],
           let title = runs.first?["text"] as? String {
            self.title = title
        } else {
            self.title = "Unknown Title"
        }
        
        // 3. Metadata (Flex Column 1: Artist, Album, Duration)
        var foundArtists: [String] = []
        var foundAlbum: String?
        var foundDuration: TimeInterval?
        
        if let columns = data["flexColumns"] as? [[String: Any]], columns.count > 1 {
            let secondCol = columns[1]
            if let textParams = secondCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
               let textData = textParams["text"] as? [String: Any],
               let runs = textData["runs"] as? [[String: Any]] {
                
                // Iterate through runs to categorize them
                // Kaset logic: Look for navigationEndpoint to identify Artist/Album
                for run in runs {
                    if let text = run["text"] as? String {
                        if let endpoint = run["navigationEndpoint"] as? [String: Any],
                           let browse = endpoint["browseEndpoint"] as? [String: Any],
                           let pageType = browse["browseEndpointContextSupportedConfigs"] as? [String: Any] {
                             
                             // Check type (Artist vs Album)
                             let config = pageType["browseEndpointContextMusicConfig"] as? [String: Any]
                             let type = config?["pageType"] as? String
                             
                             if type == "MUSIC_PAGE_TYPE_ARTIST" {
                                 foundArtists.append(text)
                             } else if type == "MUSIC_PAGE_TYPE_ALBUM" {
                                 foundAlbum = text
                             }
                        } else {
                            // If it's a timestamp (e.g. "3:45"), parse it
                            if text.contains(":") {
                                foundDuration = Self.parseDuration(text)
                            }
                        }
                    }
                }
            }
        }
        self.artists = foundArtists
        self.album = foundAlbum
        self.duration = foundDuration
        
        // 4. Thumbnail
        if let thumbContainer = data["thumbnail"] as? [String: Any],
           let musicThumb = thumbContainer["musicThumbnailRenderer"] as? [String: Any],
           let image = musicThumb["thumbnail"] as? [String: Any],
           let thumbnails = image["thumbnails"] as? [[String: Any]],
           let last = thumbnails.last,
           let urlString = last["url"] as? String {
            self.thumbnailURL = URL(string: urlString)
        } else {
            self.thumbnailURL = nil
        }
        
        // 5. Explicit Badge
        // assume false, then prove true if found the badge.
        var explicitBadgeFound = false
        
        if let badges = data["badges"] as? [[String: Any]] {
            for badge in badges {
                if let renderer = badge["musicInlineBadgeRenderer"] as? [String: Any],
                   let icon = renderer["icon"] as? [String: Any],
                   let type = icon["iconType"] as? String,
                   type == "MUSIC_EXPLICIT_BADGE" {
                    explicitBadgeFound = true
                    break
                }
            }
        }
        
        self.isExplicit = explicitBadgeFound
    }
    
    private static func parseDuration(_ string: String) -> TimeInterval? {
        let parts = string.split(separator: ":").compactMap { Double($0) }
        if parts.count == 2 { return (parts[0] * 60) + parts[1] }
        if parts.count == 3 { return (parts[0] * 3600) + (parts[1] * 60) + parts[2] }
        return nil
    }
}
