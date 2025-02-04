import Foundation
import SwiftUI
import AVKit

struct VideoItem {
    let url: URL
    let creator: String
    let description: String
}

class VideoManager: ObservableObject {
    // Only using Apple's sample streams (all unique)
    private let availableVideos = [
        VideoItem(
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!,
            creator: "Apple Demo",
            description: "Experience our cutting-edge hyperloop prototype in action! 🚄 Revolutionizing transportation #innovation"
        ),
        VideoItem(
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear1/prog_index.m3u8")!,
            creator: "Apple Streams",
            description: "Behind the scenes: Testing our hyperloop's magnetic levitation system 🧲 #engineering #future"
        ),
        VideoItem(
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear2/prog_index.m3u8")!,
            creator: "Quality Test",
            description: "Zero to 760mph in seconds! Watch our latest speed test 🏃‍♂️💨 #speed #technology"
        ),
        VideoItem(
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear3/prog_index.m3u8")!,
            creator: "HD Stream",
            description: "Inside look: Our revolutionary vacuum tube design 🌀 #aerodynamics #engineering"
        ),
        VideoItem(
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear4/prog_index.m3u8")!,
            creator: "4K Demo",
            description: "First passenger capsule reveal! 🎉 The future of travel is here #hyperloop #design"
        ),
        VideoItem(
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8")!,
            creator: "Classic Format",
            description: "Safety testing in progress: Our advanced braking system demonstration 🛑 #safety #innovation"
        ),
        VideoItem(
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear2/prog_index.m3u8")!,
            creator: "Retro Style",
            description: "Energy efficiency breakthrough: New solar-powered subsystems ☀️ #sustainable #green"
        ),
        VideoItem(
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear3/prog_index.m3u8")!,
            creator: "Vintage View",
            description: "Route planning unveiled: City-to-city in minutes! 🗺️ #infrastructure #transport"
        )
    ]
    
    @Published private(set) var videoStack: [VideoItem] = []
    @Published private(set) var currentPlayer: AVPlayer
    @Published var isShowingShareSheet = false
    @Published var itemsToShare: [Any]?
    
    private var preloadedItem: AVPlayerItem?
    private var preloadedAsset: AVAsset?
    
    init() {
        // Initialize with a dummy AVPlayer
        currentPlayer = AVPlayer()
        videoStack = availableVideos.shuffled()
        
        // Load the first video
        if let firstVideo = videoStack.first {
            let item = AVPlayerItem(url: firstVideo.url)
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
        let nextVideo = videoStack[1]
        
        // Create and start preloading the asset
        let asset = AVAsset(url: nextVideo.url)
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
                let nextItem = AVPlayerItem(url: nextVideo.url)
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
        // Get the current video URL and description
        if let currentItem = currentPlayer.currentItem,
           let urlAsset = currentItem.asset as? AVURLAsset,
           let currentVideo = videoStack.first {
            let shareText = "\(urlAsset.url)\n\n\(currentVideo.description)"
            itemsToShare = [shareText]
            isShowingShareSheet = true
        }
        
        // Move to next video after sharing
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