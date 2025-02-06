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
    
    var thumbnailUrl: URL {
        // Mux thumbnail URL format
        URL(string: "https://image.mux.com/\(playback_id)/thumbnail.jpg?time=0")!
    }
}

class VideoManager: ObservableObject {
    @Published private(set) var videoStack: [VideoItem] = []
    @Published var currentPlayer: AVPlayer
    @Published var nextPlayer: AVPlayer
    @Published private(set) var currentVideo: VideoItem?
    @Published var isShowingShareSheet = false
    @Published var itemsToShare: [Any]?
    @Published private(set) var savedVideos: [VideoItem] = []
    @Published private var isLoading = false
    @Published private(set) var allVideosSeen = false
    
    // Observers for video end notifications
    private var currentItemObserver: NSObjectProtocol?
    private var nextItemObserver: NSObjectProtocol?
    private var seenVideosFilter: BloomFilterStore
    
    // Firestore instance
    private let db = Firestore.firestore()
    
    init() async {
        print("📹 Initializing VideoManager")
        // Initialize stored properties first
        currentPlayer = AVPlayer()
        nextPlayer = AVPlayer()
        seenVideosFilter = BloomFilterStore()
        
        // Now we can safely configure players
        nextPlayer.volume = 0
        
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
                    let firstVideo = videoStack[0]
                    let item = AVPlayerItem(url: firstVideo.playbackUrl)
                    currentPlayer.replaceCurrentItem(with: item)
                    setupPlayerItem(item)
                    currentVideo = firstVideo
                    currentPlayer.play()
                    
                    // Preload the next video if available
                    if videoStack.count > 1 {
                        preloadVideo(videoStack[1])
                    }
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
    
    private func setupPlayerItem(_ item: AVPlayerItem, isNext: Bool = false) {
        // Configure buffer size for instant playback
        item.preferredForwardBufferDuration = 2  // Buffer 2 seconds for quick start
        item.preferredPeakBitRate = 0  // Let system determine best bitrate
        
        let player = isNext ? nextPlayer : currentPlayer
        
        // Remove existing observer if any
        if isNext {
            if let observer = nextItemObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        } else {
            if let observer = currentItemObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        // Add observer for video end to handle looping
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            player.seek(to: .zero)
            player.play()
        }
        
        // Store observer reference
        if isNext {
            nextItemObserver = observer
        } else {
            currentItemObserver = observer
        }
    }
    
    private func logPlayerStatus() {
        print("🎬 Current player status:")
        print("  - Video stack: \(videoStack.count) videos")
        if let currentVideo = currentVideo {
            print("  - Current video: \(currentVideo.id)")
        }
        if let nextVideo = videoStack.dropFirst().first {
            print("  - Next video: \(nextVideo.id)")
        }
    }
    

    

    
    private func preloadVideo(_ video: VideoItem) {
        print("📥 Preloading video: \(video.id)")
        
        // Create an asset for the video with custom loading options
        let resourceOptions: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        let asset = AVURLAsset(url: video.playbackUrl, options: resourceOptions)
        
        // Load essential properties asynchronously
        Task {
            do {
                // Load all essential properties for instant playback
                try await asset.load(.isPlayable, .duration)
                
                // Create and configure player item for instant playback
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 2  // Small buffer for quick start
                item.preferredPeakBitRate = 0  // Let system determine best bitrate
                
                await MainActor.run {
                    // Set up next player with the preloaded item
                    nextPlayer.replaceCurrentItem(with: item)
                    setupPlayerItem(item, isNext: true)
                    
                    // Just seek to start but don't play yet
                    nextPlayer.seek(to: .zero)
                    
                    print("✅ Next player ready with video: \(video.id)")
                }
            } catch {
                print("❌ Error preloading video: \(error.localizedDescription)")
            }
        }
    }
    
    func moveToNextVideo() {
        // Mark current video as seen and remove it
        if let currentVideo = videoStack.first {
            markVideoAsSeen(currentVideo)
            videoStack.removeFirst()
            self.currentVideo = nil
        }
        
        // If stack is getting low, load more videos
        if videoStack.count < 3 {
            loadVideos()
        }
        
        // If we've run out of videos, just log it
        if videoStack.isEmpty {
            print("📹 Video stack empty - waiting for manual reload")
            return
        }
        
        // Get the next video
        if let nextVideo = videoStack.first {
            // Swap players instantly
            let oldPlayer = currentPlayer
            currentPlayer = nextPlayer
            nextPlayer = oldPlayer
            
            // Update volume and start playing new current video
            currentPlayer.volume = 1
            currentPlayer.play()
            
            // Stop and mute old player
            nextPlayer.pause()
            nextPlayer.volume = 0
            
            // Update state
            self.currentVideo = nextVideo
            
            // Start preloading the next video if available
            if let followingVideo = videoStack.dropFirst().first {
                preloadVideo(followingVideo)
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
        // Remove observers
        if let observer = currentItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = nextItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Stop playback
        currentPlayer.pause()
        nextPlayer.pause()
    }
} 