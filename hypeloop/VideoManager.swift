import Foundation
import SwiftUI
import AVKit

struct VideoItem: Identifiable {
    let id: String
    let url: URL
    let creator: String
    let description: String
    let updatedTime: Date
    let playbackId: String
    
    init(id: String, playbackId: String, creator: String = "User", description: String = "", updatedTime: Date = Date()) {
        self.id = id
        self.playbackId = playbackId
        // Construct the Mux playback URL
        self.url = URL(string: "https://stream.mux.com/\(playbackId).m3u8")!
        self.creator = creator
        self.description = description
        self.updatedTime = updatedTime
    }
}

class VideoManager: ObservableObject {
    @Published private(set) var videoStack: [VideoItem] = []
    @Published private(set) var currentPlayer: AVPlayer
    @Published var isShowingShareSheet = false
    @Published var itemsToShare: [Any]?
    @Published private(set) var savedVideos: [VideoItem] = []
    @Published private var isLoading = false
    
    private var preloadedItem: AVPlayerItem?
    private var preloadedAsset: AVAsset?
    private var playerItemObserver: NSObjectProtocol?
    private var seenVideoIds: Set<String> = []  // Track seen videos
    
    // List of Mux playback IDs
    private let playbackIds = [
        "TxjFnTaC2zZ9pjjfPFmZruhB2vl9jKgieTDCBS3JU34",
        "taThfR9st3stsM57kclaDMUoFqXuQCyOn6VadyeLzkg",
        "1CH100Su01ZPrW0201731jh02ztThU7ALWIPOAZ1BpEV02002s",
        "00i2v700W231sYJZ02kbTho6hmzkw8l9Au4JDXN9HEpvbg"
    ]
    
    // Helper function to create VideoItems from playback IDs
    private func createVideoItems(from playbackIds: [String]) -> [VideoItem] {
        return playbackIds.enumerated().map { (index, playbackId) in
            VideoItem(
                id: "video_\(index + 1)",
                playbackId: playbackId,
                creator: "Creator \(index + 1)",
                description: "Video \(index + 1)",
                updatedTime: Date().addingTimeInterval(-Double(index * 3600)) // Each video 1 hour apart
            )
        }
    }
    
    // Computed property for fixed videos
    private var fixedVideos: [VideoItem] {
        createVideoItems(from: playbackIds)
    }
    
    init() {
        // Initialize with a dummy AVPlayer
        currentPlayer = AVPlayer()
        
        // Load the fixed list of videos
        loadVideosFromMux(initial: true)
    }
    
    func loadVideosFromMux(initial: Bool = false) {
        Task { @MainActor in
            // If not initial load and we already have videos, don't reload
            guard initial || videoStack.isEmpty else { return }
            
            // Filter out any videos we've already seen
            let newVideos = fixedVideos.filter { video in
                initial || !seenVideoIds.contains(video.id)
            }
            
            if initial {
                print("🔄 Setting initial video stack with \(newVideos.count) videos")
                self.videoStack = newVideos
            } else {
                print("➕ Appending \(newVideos.count) new videos to stack")
                self.videoStack.append(contentsOf: newVideos)
            }
            
            if self.currentPlayer.currentItem == nil, let firstVideo = self.videoStack.first {
                print("▶️ Loading first video: \(firstVideo.id)")
                let item = AVPlayerItem(url: firstVideo.url)
                self.currentPlayer.replaceCurrentItem(with: item)
                self.setupPlayerItem(item)
            }
        }
    }
    
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func setupPlayerItem(_ item: AVPlayerItem) {
        // Remove existing observer
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Add new observer for looping
        playerItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.currentPlayer.seek(to: .zero)
            self?.currentPlayer.play()
        }
    }
    
    private func cleanupCurrentVideo() {
        currentPlayer.pause()
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemObserver = nil
        }
        currentPlayer.replaceCurrentItem(with: nil)
    }
    
    func preloadNextVideo() {
        guard videoStack.count > 1 else {
            print("⚠️ Cannot preload - no more videos in stack")
            return
        }
        let nextVideo = videoStack[1]
        print("🔄 Preloading next video: \(nextVideo.id)")
        
        let asset = AVAsset(url: nextVideo.url)
        preloadedAsset = asset
        
        Task {
            print("📥 Starting preload of video properties for: \(nextVideo.id)")
            await asset.loadValues(forKeys: ["playable", "duration"])
            
            if asset === preloadedAsset {
                let item = AVPlayerItem(asset: asset)
                await MainActor.run {
                    print("✅ Preload complete for video: \(nextVideo.id)")
                    self.preloadedItem = item
                }
            } else {
                print("⚠️ Preload cancelled - asset no longer current")
            }
        }
    }
    
    func moveToNextVideo() {
        cleanupCurrentVideo()
        
        // Mark current video as seen and remove it
        if let currentVideo = videoStack.first {
            seenVideoIds.insert(currentVideo.id)
            videoStack.removeFirst()
        }
        
        // If stack is getting low, load more videos
        if videoStack.count < 3 {
            loadVideosFromMux()
        }
        
        // Reset seen videos if we've seen them all
        if seenVideoIds.count == videoStack.count && !videoStack.isEmpty {
            seenVideoIds.removeAll()
        }
        
        // Use preloaded item if available
        if let preloadedItem = preloadedItem {
            currentPlayer.replaceCurrentItem(with: preloadedItem)
            setupPlayerItem(preloadedItem)
            self.preloadedItem = nil
            self.preloadedAsset = nil
            currentPlayer.play()
        } else {
            // Fallback to regular loading
            if let nextVideo = videoStack.first {
                let nextItem = AVPlayerItem(url: nextVideo.url)
                currentPlayer.replaceCurrentItem(with: nextItem)
                setupPlayerItem(nextItem)
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
        if let currentVideo = videoStack.first {
            // Only save if not already saved
            if !savedVideos.contains(where: { $0.id == currentVideo.id }) {
                savedVideos.append(currentVideo)
            }
        }
        moveToNextVideo()
    }
    
    func removeSavedVideo(at indexSet: IndexSet) {
        savedVideos.remove(atOffsets: indexSet)
    }
    
    deinit {
        cleanupCurrentVideo()
    }
} 