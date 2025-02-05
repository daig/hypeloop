import Foundation
import SwiftUI
import AVKit
import FirebaseFunctions

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
    
    // Shared Functions instance
    private let functions = Functions.functions(region: "us-central1")
    
    init() {
        // Initialize with a dummy AVPlayer
        currentPlayer = AVPlayer()
        
        // Load videos from Mux
        loadVideosFromMux(initial: true)
    }
    
    func loadVideosFromMux(initial: Bool = false) {
        Task { @MainActor in
            // If not initial load and we already have videos, don't reload
            guard initial || videoStack.isEmpty else { return }
            
            isLoading = true
            
            do {
                print("📡 Fetching videos from Mux...")
                
                let callable = functions.httpsCallable("listMuxAssets")
                let result = try await callable.call([
                    "debug": true,
                    "timestamp": Date().timeIntervalSince1970,
                    "client": "ios",
                    "requestId": UUID().uuidString
                ])
                
                guard let response = result.data as? [String: Any],
                      let videoData = response["videos"] as? [[String: Any]] else {
                    print("❌ Invalid response format")
                    return
                }
                
                print("✅ Received \(videoData.count) videos from Mux")
                
                // Convert the response data to VideoItems
                let newVideos = videoData.compactMap { data -> VideoItem? in
                    guard let id = data["id"] as? String,
                          let playbackId = data["playback_id"] as? String,
                          let creator = data["creator"] as? String,
                          let description = data["description"] as? String,
                          let createdAt = data["created_at"] as? Double else {
                        print("⚠️ Skipping invalid video data")
                        return nil
                    }
                    
                    return VideoItem(
                        id: id,
                        playbackId: playbackId,
                        creator: creator,
                        description: description,
                        updatedTime: Date(timeIntervalSince1970: createdAt / 1000) // Convert from milliseconds to seconds
                    )
                }
                
                // Filter out videos we've already seen
                let filteredVideos = newVideos.filter { video in
                    initial || !seenVideoIds.contains(video.id)
                }
                
                if initial {
                    print("🔄 Setting initial video stack with \(filteredVideos.count) videos")
                    self.videoStack = filteredVideos
                } else {
                    print("➕ Appending \(filteredVideos.count) new videos to stack")
                    self.videoStack.append(contentsOf: filteredVideos)
                }
                
                if self.currentPlayer.currentItem == nil, let firstVideo = self.videoStack.first {
                    print("▶️ Loading first video: \(firstVideo.id)")
                    let item = AVPlayerItem(url: firstVideo.url)
                    self.currentPlayer.replaceCurrentItem(with: item)
                    self.setupPlayerItem(item)
                    self.currentPlayer.play()  // Start playing immediately
                    self.preloadNextVideo()    // And preload the next video
                }
                
            } catch {
                print("❌ Error fetching videos: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("🔍 Error details - Domain: \(nsError.domain), Code: \(nsError.code)")
                    if let details = nsError.userInfo["details"] as? [String: Any] {
                        print("📝 Error details: \(details)")
                    }
                }
            }
            
            isLoading = false
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
            
            // Immediately start preloading the next video
            preloadNextVideo()
        } else {
            // Fallback to regular loading
            if let nextVideo = videoStack.first {
                let nextItem = AVPlayerItem(url: nextVideo.url)
                currentPlayer.replaceCurrentItem(with: nextItem)
                setupPlayerItem(nextItem)
                currentPlayer.play()
                
                // Immediately start preloading the next video
                preloadNextVideo()
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