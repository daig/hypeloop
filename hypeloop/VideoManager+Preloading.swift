//
//  VideoManager+Preloading.swift
//  hypeloop
//

import SwiftUI
import AVKit

extension VideoManager {
    
    /// Sets up an AVPlayerItem for looping playback on either the current or next player.
    /// - Parameters:
    ///   - item: The AVPlayerItem to loop.
    ///   - isNext: Whether this is for the `nextPlayer`.
    func setupPlayerItem(_ item: AVPlayerItem, isNext: Bool = false) {
        
        let player = isNext ? nextPlayer : currentPlayer
        
        // Create a new player looper
        let looper = AVPlayerLooper(player: player, templateItem: item)
        
        if isNext { nextLooper = looper }
        else      { currentLooper = looper }
    }
    
    /// Preloads the specified video using the `nextPlayer` to minimize delay during playback transition.
    /// - Parameter video: The `VideoItem` to preload.
    @MainActor
    func preloadVideo(_ video: VideoItem) {
        print("📥 Preloading video: \(video.id)")
        let asset = AVURLAsset(url: video.playbackUrl, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        
        Task {
            do {
                try await asset.load(.isPlayable, .duration)
                
                // Ensure stack and video are still valid
                guard !videoStack.isEmpty else {
                    print("📥 Preload canceled: stack is empty.")
                    return
                }
                guard videoStack.contains(where: { $0.id == video.id }) else {
                    print("📥 Preload canceled: video \(video.id) not in stack.")
                    return
                }
                
                // Create the item
                let item = AVPlayerItem(asset: asset)
                
                nextPlayer.replaceCurrentItem(with: item)
                setupPlayerItem(item, isNext: true)
                
                // Start playing in the background, volume=0
                nextPlayer.seek(to: .zero) { _ in
                    self.nextPlayer.play()
                }
                print("✅ Next player ready with video: \(video.id)")

            } catch { print("❌ Error preloading video: \(error.localizedDescription)") }
        }
    }
}