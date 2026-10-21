//
//  YouTubeOAuthClient.swift
//  YouTubeSDK
//
//  Created by Aarav Gupta on 26/12/25.
//

import Foundation

/// Acts as the Session Manager for the entire SDK.
/// Use this to Save, Load, and Validate cookies.
public actor YouTubeOAuthClient {
    
    private let network: NetworkClient
    public static let sharedCookieKey = "youtube_user_cookies"
    
    /// Initializes the Auth Client.
    /// automatically loads the saved cookies from Keychain to perform validation checks.
    public init() {
        let cookies = Keychain.load(key: Self.sharedCookieKey)
        // We use the iOS client configuration for generic account checks, as it's highly reliable.
        let context = InnerTubeContext(client: ClientConfig.ios, cookies: cookies)
        self.network = NetworkClient(context: context)
    }
    
    // MARK: - Validation
    
    /// Verifies if the currently stored cookies are valid by hitting a private endpoint.
    /// - Returns: `true` if logged in, `false` if guest/expired.
    public func validateSession() async -> Bool {
        do {
            // 'account/account_menu' is a lightweight endpoint that returns user info.
            // It doesn't require a complex body, just the Cookie header.
            let data = try await network.get("account/account_menu")
            
            // If the response contains specific account renderers, the session is active.
            if let json = String(data: data, encoding: .utf8),
               json.contains("googleAccountHeaderRenderer") {
                return true
            }
        } catch {
            print("⚠️ Auth Validation Failed: \(error)")
        }
        return false
    }
    
    // MARK: - Static Helpers (Developer Experience)
    
    /// Saves the cookies string (from GoogleLoginView) to the secure Keychain.
    public static func saveCookies(_ cookies: String) {
        Keychain.save(cookies, key: sharedCookieKey)
    }
    
    /// Loads the saved cookies string to pass into other Clients.
    public static func loadCookies() -> String? {
        Keychain.load(key: sharedCookieKey)
    }
    
    /// Wipes the session (Logout).
    public static func logout() {
        Keychain.delete(key: sharedCookieKey)
    }
}
