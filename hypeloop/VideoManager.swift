import Foundation
import SwiftUI
import AVKit

class VideoManager: ObservableObject {
    // Only using Apple's sample streams (all unique)
    private let availableVideos = [
        // Main demo stream
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8",
        // 16:9 streams at different qualities
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear1/prog_index.m3u8",
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear2/prog_index.m3u8",
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear3/prog_index.m3u8",
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear4/prog_index.m3u8",
        // 4:3 streams at different qualities
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8",
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear2/prog_index.m3u8",
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear3/prog_index.m3u8"
    ].map { URL(string: $0)! }
    
    @Published private(set) var videoStack: [URL] = []
    @Published private(set) var currentPlayer: AVPlayer
    
    private var preloadedItem: AVPlayerItem?
    private var preloadedAsset: AVAsset?
    
    init() {
        // Initialize with a dummy AVPlayer
        currentPlayer = AVPlayer()
        videoStack = availableVideos.shuffled()
        
        // Load the first video
        if let firstVideo = videoStack.first {
            let item = AVPlayerItem(url: firstVideo)
            currentPlayer.replaceCurrentItem(with: item)
        }
    }
    
    private func cleanupCurrentVideo() {
        currentPlayer.pause()
        // Don't nil out the player, just remove its item
        currentPlayer.replaceCurrentItem(with: nil)
    }
    
    func preloadNextVideo() {
        guard videoStack.count > 1 else { return }
        let nextVideoURL = videoStack[1]
        
        // Create and start preloading the asset
        let asset = AVAsset(url: nextVideoURL)
        preloadedAsset = asset
        
        // Preload essential properties
        Task {
            await asset.loadValues(forKeys: ["playable", "duration"])
            
            // Only create the player item if this is still our preloaded asset
            if asset === preloadedAsset {
                let item = AVPlayerItem(asset: asset)
                
                // Switch to main thread for UI updates
                await MainActor.run {
                    self.preloadedItem = item
                }
            }
        }
    }
    
    func moveToNextVideo() {
        cleanupCurrentVideo()
        
        // Remove the current video from the stack
        if !videoStack.isEmpty {
            videoStack.removeFirst()
        }
        
        // If stack is empty, reshuffle all videos
        if videoStack.isEmpty {
            videoStack = availableVideos.shuffled()
        }
        
        // Use preloaded item if available, otherwise create new one
        if let preloadedItem = preloadedItem {
            currentPlayer.replaceCurrentItem(with: preloadedItem)
            self.preloadedItem = nil
            self.preloadedAsset = nil
            currentPlayer.play()
        } else {
            // Fallback to regular loading if preload wasn't ready
            if let nextVideo = videoStack.first {
                let nextItem = AVPlayerItem(url: nextVideo)
                currentPlayer.replaceCurrentItem(with: nextItem)
                currentPlayer.play()
            }
        }
    }
    
    func handleRightSwipe() {
        // Right swipe indicates "like" or positive action
        // For now, just move to next video
        moveToNextVideo()
    }
    
    func handleLeftSwipe() {
        // Left swipe indicates "dislike" or negative action
        // For now, just move to next video
        moveToNextVideo()
    }
    
    func handleUpSwipe() {
        // Up swipe indicates "share" or "send" action
        // For now, just move to next video
        moveToNextVideo()
    }
    
    func handleDownSwipe() {
        // Down swipe indicates "save" action
        // For now, just move to next video
        moveToNextVideo()
    }
    
    deinit {
        cleanupCurrentVideo()
    }
} 