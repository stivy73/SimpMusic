//
//  YouTubeMusicClient.swift
//  YouTubeSDK
//
//  Created by Aarav Gupta on 26/12/25.
//

import Foundation

public actor YouTubeMusicClient {
    
    let network: NetworkClient
    let cookies: String?
    
    public init(cookies: String? = nil) {
        self.cookies = cookies
        let context = InnerTubeContext(client: ClientConfig.webRemix, cookies: cookies)
        self.network = NetworkClient(context: context, baseURL: YouTubeSDKConstants.URLS.API.youtubeMusicInnerTubeURL)
    }

    public func search(_ query: String) async throws -> [YouTubeMusicSong] {
        let data = try await network.get("search", body: ["query": query])
        return await parseMusicItems(from: data)
    }
    
    public func getSearchSuggestions(query: String) async throws -> [String] {
        let body = ["input": query]
        let data = try await network.get("music/get_search_suggestions", body: body)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        
        let suggestions = await findAll(key: "searchSuggestionRenderer", in: json)
        return suggestions.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            
            // Try both parsing styles found in discovery
            if let nav = dict["navigationEndpoint"] as? [String: Any],
               let search = nav["searchEndpoint"] as? [String: Any],
               let query = search["query"] as? String {
                return query
            }
            
            if let sugg = dict["suggestion"] as? [String: Any],
               let runs = sugg["runs"] as? [[String: Any]] {
                return runs.compactMap { $0["text"] as? String }.joined()
            }
            
            return nil
        }
    }
}
