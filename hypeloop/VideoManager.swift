import Foundation
import SwiftUI
import AVKit
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth

struct VideoItem: Codable {
    let id: String
    let playback_id: String
    let creator: String       // Hash of the creator's identifier
    let display_name: String  // Generated display name
    let description: String
    let created_at: Double
    let status: String
    
    var playbackUrl: URL {
        URL(string: "https://stream.mux.com/\(playback_id).m3u8")!
    }
}

class VideoManager: ObservableObject {
    @Published private(set) var videoStack: [VideoItem] = []
    @Published var currentPlayer: AVQueuePlayer
    @Published private(set) var currentVideo: VideoItem?
    @Published var isShowingShareSheet = false
    @Published var itemsToShare: [Any]?
    @Published private(set) var savedVideos: [VideoItem] = []
    @Published private var isLoading = false
    @Published private(set) var allVideosSeen = false
    
    private var preloadedItem: AVPlayerItem?
    private var preloadedAsset: AVAsset?
    private var playerLooper: AVPlayerLooper?
    private var seenVideosFilter: BloomFilterStore
    
    // Firestore instance
    private let db = Firestore.firestore()
    
    init() async {
        print("📹 Initializing VideoManager")
        // Initialize with a dummy AVQueuePlayer
        currentPlayer = AVQueuePlayer()
        
        // Initialize bloom filter store and wait for it to load
        print("📹 Creating BloomFilterStore")
        seenVideosFilter = BloomFilterStore()
        
        // Wait for bloom filter to load
        print("📹 Waiting for bloom filter to load...")
        let startTime = Date()
        while !seenVideosFilter.isLoaded {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            print("⏳ Waiting for bloom filter to load... Time elapsed: \(Int(-startTime.timeIntervalSinceNow))s")
        }
        print("📹 Bloom filter loaded after \(Int(-startTime.timeIntervalSinceNow))s")
        
        // Now that bloom filter is loaded, perform initial video load
        print("📹 Starting initial video load")
        await loadVideos(initial: true)
        
        print("📹 VideoManager initialization complete")
    }
    

    
    private func markVideoAsSeen(_ video: VideoItem) {
        print("📹 Marking video as seen: \(video.id)")
        seenVideosFilter.add(video.id)
        
        // Note: BloomFilterStore automatically handles persistence to Firebase
        // and syncing across devices, so we don't need the additional Firestore calls
    }
    
    func loadVideos(initial: Bool = false) {
        Task { @MainActor in
            // Always allow loading on initial or when stack is empty
            if !initial && !videoStack.isEmpty {
                print("📹 Skipping video load - stack not empty")
                return
            }
            
            isLoading = true
            
            do {
                print("📡 Fetching videos from Firestore...")
                
                // Debug: First check all videos regardless of status
                let allVideos = try await db.collection("videos").getDocuments()
                print("📊 Debug: Found \(allVideos.documents.count) total videos in Firestore")
                print("📊 Debug: Video statuses: \(allVideos.documents.map { $0.data()["status"] as? String ?? "unknown" })")
                
                // Now perform our filtered query
                let snapshot = try await db.collection("videos")
                    .whereField("status", isEqualTo: "ready")
                    .order(by: "created_at", descending: true)
                    .limit(to: 50)
                    .getDocuments()
                
                print("📹 Starting video processing")
                let startTime = Date()
                
                // Wait for bloom filter to load before processing videos
                while !seenVideosFilter.isLoaded {
                    print("⏳ Waiting for bloom filter to load... Time elapsed: \(Int(-startTime.timeIntervalSinceNow))s")
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
                
                print("📹 Bloom filter loaded after \(Int(-startTime.timeIntervalSinceNow))s. Processing videos...")
                
                let newVideos = snapshot.documents.compactMap { document -> VideoItem? in
                    do {
                        let video = try document.data(as: VideoItem.self)
                        print("📹 Successfully decoded video: id=\(video.id), creator=\(video.creator)")
                        return video
                    } catch {
                        print("❌ Error decoding video: \(error.localizedDescription)")
                        print("📄 Document data: \(document.data())")
                        return nil
                    }
                }
                
                print("✅ Received \(newVideos.count) ready videos")
                print("📹 Current bloom filter state - isLoaded: \(seenVideosFilter.isLoaded)")
                
                print("📹 Processing \(newVideos.count) videos for filtering")
                var seenCount = 0
                // Filter out videos we've already seen
                let unseenVideos = newVideos.filter { video in
                    let isSeen = self.seenVideosFilter.mightContain(video.id)
                    if isSeen { seenCount += 1 }
                    print("📹 Video \(video.id): seen=\(isSeen)")
                    return !isSeen
                }
                
                print("📹 Filtering complete - Total: \(newVideos.count), Seen: \(seenCount), Unseen: \(unseenVideos.count)")
                
                // Update allVideosSeen status
                allVideosSeen = unseenVideos.isEmpty && !newVideos.isEmpty
                
                // Add new videos to the stack
                videoStack.append(contentsOf: unseenVideos)
                
                // If this is the initial load and we have videos, set up the first video
                if initial && !videoStack.isEmpty {
                    setupVideo(videoStack[0])
                }
                
                // Preload the next video if available
                if let nextVideo = videoStack.dropFirst().first {
                    preloadVideo(nextVideo)
                }
                
                isLoading = false
                
            } catch {
                print("❌ Error loading videos:", error)
                print("📄 Error details:", (error as NSError).userInfo)
                isLoading = false
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
        // Remove existing looper
        playerLooper?.disableLooping()
        playerLooper = nil
        
        // Create new looper for smooth playback
        playerLooper = AVPlayerLooper(player: currentPlayer, templateItem: item)
    }
    
    private func cleanupCurrentVideo() {
        currentPlayer.pause()
        playerLooper?.disableLooping()
        playerLooper = nil
        currentPlayer.removeAllItems()
        print("🎬 Queue cleared during cleanup")
    }
    
    private func logQueueStatus() {
        let items = currentPlayer.items()
        print("🎬 Current queue status:")
        print("  - Total items: \(items.count)")
        for (index, item) in items.enumerated() {
            if let urlAsset = item.asset as? AVURLAsset {
                let url = urlAsset.url
                if let playbackId = url.lastPathComponent.split(separator: ".").first {
                    print("  - [\(index)] Video ID: \(playbackId)")
                }
            }
        }
    }
    
    private func setupVideo(_ video: VideoItem) {
        print("🎬 Setting up video: \(video.id)")
        
        // Create AVPlayerItem for the video
        let playerItem = AVPlayerItem(url: video.playbackUrl)
        
        // Configure the player item
        playerItem.preferredForwardBufferDuration = 5  // Buffer 5 seconds ahead
        
        // Clear existing queue and add the new item
        currentPlayer.removeAllItems()
        print("🎬 Queue cleared")
        
        currentPlayer.insert(playerItem, after: nil)
        print("🎬 Added initial video to queue: \(video.id)")
        logQueueStatus()
        
        setupPlayerItem(playerItem)
        
        // Update current video
        currentVideo = video
        
        // Add next video to queue if available
        if let nextVideo = videoStack.dropFirst().first {
            preloadVideo(nextVideo)
        }
        
        // Start playing
        currentPlayer.play()
    }
    
    private func preloadVideo(_ video: VideoItem) {
        print("📥 Preloading video: \(video.id)")
        
        // Create an asset for the video
        let asset = AVURLAsset(url: video.playbackUrl)
        preloadedAsset = asset
        
        // Load essential properties asynchronously
        Task {
            do {
                // Load playable status and duration
                try await asset.load(.isPlayable, .duration)
                
                // Only proceed if this is still the asset we want to preload
                guard asset === preloadedAsset else {
                    print("⚠️ Asset changed during preload, cancelling")
                    return
                }
                
                // Create and configure player item
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 5  // Buffer 5 seconds ahead
                
                await MainActor.run {
                    // Only add to queue if we're still preloading the same asset
                    if asset === preloadedAsset {
                        print("✅ Preload complete for video: \(video.id)")
                        self.preloadedItem = item
                        
                        // Add to queue
                        if let currentLastItem = self.currentPlayer.items().last {
                            self.currentPlayer.insert(item, after: currentLastItem)
                            print("🎬 Added preloaded video to queue: \(video.id)")
                            logQueueStatus()
                        }
                    } else {
                        print("⚠️ Asset changed after item creation, discarding")
                    }
                }
            } catch {
                print("❌ Error preloading video: \(error.localizedDescription)")
                preloadedAsset = nil
                preloadedItem = nil
            }
        }
    }
    
    func moveToNextVideo() {
        cleanupCurrentVideo()
        
        // Mark current video as seen and remove it
        if let currentVideo = videoStack.first {
            markVideoAsSeen(currentVideo)
            videoStack.removeFirst()
        }
        
        // If stack is getting low, load more videos
        if videoStack.count < 3 {
            loadVideos()
        }
        
        // If we've run out of videos, just log it
        if videoStack.isEmpty {
            print("📹 Video stack empty - waiting for manual reload")
        }
        
        // Use preloaded item if available
        if let preloadedItem = preloadedItem {
            currentPlayer.replaceCurrentItem(with: preloadedItem)
            setupPlayerItem(preloadedItem)
            self.preloadedItem = nil
            self.preloadedAsset = nil
            currentPlayer.play()
            
            // Immediately start preloading the next video
            if let nextVideo = videoStack.dropFirst().first {
                preloadVideo(nextVideo)
            }
        } else {
            // Fallback to regular loading
            if let nextVideo = videoStack.first {
                let nextItem = AVPlayerItem(url: nextVideo.playbackUrl)
                currentPlayer.replaceCurrentItem(with: nextItem)
                setupPlayerItem(nextItem)
                currentPlayer.play()
                
                // Immediately start preloading the next video
                if let followingVideo = videoStack.dropFirst().first {
                    preloadVideo(followingVideo)
                }
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