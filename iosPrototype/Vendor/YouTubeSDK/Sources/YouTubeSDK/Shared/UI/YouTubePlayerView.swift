//
//  YouTubePlayerView.swift
//  YouTubeSDK
//
//  Created by Aarav Gupta on 01/01/26.
//

import SwiftUI
import AVKit

public struct YouTubePlayerView: View {
    
    @ObservedObject var player: YouTubeAVPlayer
    var mode: PlayerMode
    
    public enum PlayerMode {
        case video
        case audio
    }
    
    public init(player: YouTubeAVPlayer, mode: PlayerMode = .video) {
        self.player = player
        self.mode = mode
    }
    
    public var body: some View {
        ZStack {
            Color.black
            
            VideoPlayer(player: player)
                .disabled(player.isLoading)
            
            if mode == .audio || player.isLoading {
                ArtworkOverlay()
            }
            
            if player.isLoading {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
            }
            
            if let errorText = player.playbackError {
                ContentUnavailableView("Playback Error", systemImage: "exclamationmark.triangle", description: Text(errorText))
            }
        }
    }
    
    @ViewBuilder
    private func ArtworkOverlay() -> some View {
        ZStack {
            if let urlString = player.currentVideo?.thumbnailURL, let url = URL(string: urlString) {
                
                // Background Blur
                AsyncImage(url: url) { image in
                    image.resizable()
                         .aspectRatio(contentMode: .fill)
                         .cornerRadius(12)
//                         .blur(radius: 20)
                } placeholder: {
                    Color.black
                }
            } else {
                Color.black
            }
        }
    }
}
