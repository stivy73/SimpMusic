//
//  YouTubeMusicClient+Parsing.swift
//  YouTubeSDK
//
//  Created by Aarav Gupta on 13/03/26.
//

import Foundation

extension YouTubeMusicClient {
    
    // MARK: - Internal Parsing Helpers
    
    func parseMusicItems(from data: Data) -> [YouTubeMusicSong] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let items = findAll(key: "musicResponsiveListItemRenderer", in: json)
        return items.compactMap { ($0 as? [String: Any]).flatMap { YouTubeMusicSong(from: $0) } }
    }

    func parseHomePage(from data: Data) -> YouTubeMusicHomePage {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return YouTubeMusicHomePage(sections: [], continuationToken: nil)
        }

        let sections = parseSections(from: json)
        let continuationToken = findContinuationToken(in: json)
        return YouTubeMusicHomePage(sections: sections, continuationToken: continuationToken)
    }
    
    func parseSections(from json: [String: Any]) -> [YouTubeMusicSection] {
        var sections: [YouTubeMusicSection] = []
        
        // 1. Carousels (Horizontal)
        let carousels = findAll(key: "musicCarouselShelfRenderer", in: json)
        for carousel in carousels {
            if let dict = carousel as? [String: Any],
               let section = YouTubeMusicSection(from: dict) {
                sections.append(section)
            }
        }
        
        // 2. Shelves (Vertical)
        let shelves = findAll(key: "musicShelfRenderer", in: json)
        for shelf in shelves {
            if let dict = shelf as? [String: Any],
               let section = YouTubeMusicSection(from: dict) {
                sections.append(section)
            }
        }
        
        return sections
    }
    
    /// Recursively finds all dictionaries with a specific key.
    func findAll(key: String, in container: Any) -> [Any] {
        var results: [Any] = []
        if let dict = container as? [String: Any] {
            if let found = dict[key] { results.append(found) }
            for value in dict.values { results.append(contentsOf: findAll(key: key, in: value)) }
        } else if let array = container as? [Any] {
            for element in array { results.append(contentsOf: findAll(key: key, in: element)) }
        }
        return results
    }

    func findContinuationToken(in container: Any) -> String? {
        if let dict = container as? [String: Any] {
            if let token = dict["continuation"] as? String { return token }
            if let continuationData = (dict["continuationEndpoint"] as? [String: Any])?["continuationCommand"] as? [String: Any],
               let token = continuationData["token"] as? String {
                return token
            }
            for value in dict.values {
                if let found = findContinuationToken(in: value) {
                    return found
                }
            }
        } else if let array = container as? [Any] {
            for element in array {
                if let found = findContinuationToken(in: element) {
                    return found
                }
            }
        }
        return nil
    }
}
