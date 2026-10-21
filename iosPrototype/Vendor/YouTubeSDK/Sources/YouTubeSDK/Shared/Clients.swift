//
//  Clients.swift
//  YouTubeSDK
//
//  Created by Aarav Gupta on 26/12/25.
//

import Foundation

/// Defines the static identity of a YouTube Client.
/// This struct holds the "Magic Strings" required to mimic an official app.
/// https://github.com/zerodytrash/YouTube-Internal-Clients <- The goat
public struct ClientConfig: Sendable {
    
    public let name: String            // The internal client name (e.g., "IOS", "WEB_REMIX")
    public let version: String         // The app version (e.g., "19.10.5")
    public let apiKey: String          // The Google API Key
    public let userAgent: String       // The User-Agent header string
    public let clientNameID: String    // The numeric ID used in some stats logs
    
    // MARK: - The Golden List of Presets
    
    /// The Standard Web Client. Best for Charts and Public Data.
    public static let web = ClientConfig(
        name: "WEB",
        version: "2.20240308.00.00",
        apiKey: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8", // From zerodytrash (Web)
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        clientNameID: "1"
    )
    
    /// The YouTube Music Web Client. Best for Lyrics and Metadata.
    public static let webRemix = ClientConfig(
        name: "WEB_REMIX",
        version: "1.20240308.00.00",
        apiKey: "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30", // From zerodytrash (Web Music)
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        clientNameID: "67"
    )
    
    public static let webMusicAnalytics = ClientConfig(
        name: "WEB_MUSIC_ANALYTICS",
        version: "2.0",
        apiKey: "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30", // From zerodytrash (Web Music)
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        clientNameID: "31"
    )
    
    /// The standard iOS Client. Best for generic Video and Search.
    public static let ios = ClientConfig(
        name: "IOS",
        version: "20.11.6",
        apiKey: "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc", // From zerodytrash
        userAgent: "com.google.ios.youtube/20.11.6 (iPhone10,4; U; CPU iOS 16_7_7 like Mac OS X)",
        clientNameID: "5"
    )
    
    /// The YouTube Music Native Client. Best for High-Quality Audio.
    public static let iosMusic = ClientConfig(
        name: "IOS_MUSIC",
        version: "6.43.52", // Recent stable version
        apiKey: "AIzaSyBAETezhkwP0ZWA02RsqT1zu78Fpt0bC_s", // From zerodytrash (iOS Music)
        userAgent: "com.google.ios.youtube/20.11.6 (iPhone10,4; U; CPU iOS 16_7_7 like Mac OS X)",
        clientNameID: "26"
    )
    
    /// The Android Client. Reliable backup for Video.
    public static let android = ClientConfig(
        name: "ANDROID",
        version: "19.35.36",
        apiKey: "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w", // From zerodytrash
        userAgent: "com.google.android.youtube/19.35.36 (Linux; U; Android 13; en_US) gzip",
        clientNameID: "3"
    )
    
    /// The YouTube Music Native Client. Best for High-Quality Audio.
    public static let androidMusic = ClientConfig(
        name: "ANDROID_MUSIC",
        version: "6.43.52", // Recent stable version
        apiKey: "AIzaSyAOghZGza2MQSZkY_zfZ370N-PUdXEo8AI", // From zerodytrash (Android Music)
        userAgent: "com.google.android.apps.youtube.music/6.43.52 (Linux; U; Android 13; en_US) gzip",
        clientNameID: "21"
    )
    
    /// The TV Client. Essential for the "Code" Authentication flow.
    public static let tv = ClientConfig(
        name: "TVHTML5",
        version: "7.20250219.14.00",
        apiKey: "AIzaSyBUPetSUmoZL-OhlxA7wSac5XinrygCqMo", // Generic Safe Key
        userAgent: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version",
        clientNameID: "7"
    )
}
