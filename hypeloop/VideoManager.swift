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
    @Published var nextPlayer: AVQueuePlayer
    @Published private(set) var currentVideo: VideoItem?
    @Published var isShowingShareSheet = false
    @Published var itemsToShare: [Any]?
    @Published private(set) var savedVideos: [VideoItem] = []
    @Published private var isLoading = false
    @Published private(set) var allVideosSeen = false
    
    // Player loopers for smooth video looping
    private var currentLooper: AVPlayerLooper?
    private var nextLooper: AVPlayerLooper?
    private var seenVideosFilter: BloomFilterStore
    
    // Firestore instance
    private let db = Firestore.firestore()
    
    init() async {
        print("📹 Initializing VideoManager")
        // Initialize players and the bloom filter.
        currentPlayer = AVQueuePlayer()
        nextPlayer = AVQueuePlayer()
        seenVideosFilter = BloomFilterStore()
        
        // Configure nextPlayer to be muted initially
        nextPlayer.volume = 0
        
        // Wait for the bloom filter to load
        print("📹 Waiting for bloom filter to load...")
        let startTime = Date()
        while !seenVideosFilter.isLoaded {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            print("⏳ Waiting... elapsed: \(Int(-startTime.timeIntervalSinceNow))s")
        }
        print("📹 Bloom filter loaded after \(Int(-startTime.timeIntervalSinceNow))s")
        
        // Perform the initial video load
        print("📹 Starting initial video load")
        await loadVideos(initial: true)
        
        print("📹 VideoManager initialization complete")
    }
    
    private func markVideoAsSeen(_ video: VideoItem) {
        print("📹 Marking video as seen: \(video.id)")
        seenVideosFilter.add(video.id)
    }
    
    func loadVideos(initial: Bool = false) {
        Task { @MainActor in
            if !initial && !videoStack.isEmpty {
                print("📹 Skipping load – stack not empty")
                return
            }
            
            isLoading = true
            
            do {
                print("📡 Fetching videos from Firestore...")
                // (Optional) debug fetch of all videos
                let allVideos = try await db.collection("videos").getDocuments()
                print("📊 Debug: total videos in Firestore = \(allVideos.documents.count)")
                
                // Actual fetch: only "ready" videos
                let snapshot = try await db.collection("videos")
                    .whereField("status", isEqualTo: "ready")
                    .order(by: "created_at", descending: true)
                    .limit(to: 50)
                    .getDocuments()
                
                print("📹 Starting video processing")
                let startTime = Date()
                while !seenVideosFilter.isLoaded {
                    print("⏳ Waiting for bloom filter... elapsed: \(Int(-startTime.timeIntervalSinceNow))s")
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                
                // Decode all snapshots
                let newVideos = snapshot.documents.compactMap { document -> VideoItem? in
                    do {
                        let video = try document.data(as: VideoItem.self)
                        print("📹 Decoded video: \(video.id)")
                        return video
                    } catch {
                        print("❌ Error decoding video: \(error.localizedDescription)")
                        return nil
                    }
                }
                
                print("✅ Received \(newVideos.count) ready videos")
                
                // Filter out "seen" videos
                var seenCount = 0
                let unseenVideos = newVideos.filter { video in
                    let isSeen = self.seenVideosFilter.mightContain(video.id)
                    if isSeen { seenCount += 1 }
                    return !isSeen
                }
                
                print("📹 Filtered videos: total \(newVideos.count), seen \(seenCount), unseen \(unseenVideos.count)")
                allVideosSeen = unseenVideos.isEmpty && !newVideos.isEmpty
                
                // Append unseen videos to stack
                videoStack.append(contentsOf: unseenVideos)
                
                // If this was the first load and there's at least one video, set up the first video
                if initial && !videoStack.isEmpty {
                    let firstVideo = videoStack[0]
                    let item = AVPlayerItem(url: firstVideo.playbackUrl)
                    currentPlayer.replaceCurrentItem(with: item)
                    setupPlayerItem(item)
                    currentVideo = firstVideo
                    currentPlayer.play()
                    
                    // Preload next if available
                    if videoStack.count > 1 {
                        preloadVideo(videoStack[1])
                    }
                }
                
                isLoading = false
            } catch {
                print("❌ Error loading videos: \(error.localizedDescription)")
                isLoading = false
            }
        }
    }
    
    private func setupPlayerItem(_ item: AVPlayerItem, isNext: Bool = false) {
        item.preferredForwardBufferDuration = 2
        item.preferredPeakBitRate = 0
        
        let player = isNext ? nextPlayer : currentPlayer
        
        // Create a new player looper
        let looper = AVPlayerLooper(player: player, templateItem: item)
        
        if isNext {
            nextLooper = looper
        } else {
            currentLooper = looper
        }
    }
    
    private func preloadVideo(_ video: VideoItem) {
        print("📥 Preloading video: \(video.id)")
        let asset = AVURLAsset(url: video.playbackUrl, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        
        Task {
            do {
                // Load a couple of properties we need
                try await asset.load(.isPlayable, .duration)
                
                // --- GUARD CHECKS: ensure stack and video are still valid ---
                guard !videoStack.isEmpty else {
                    print("📥 Preload canceled: stack is empty.")
                    return
                }
                guard videoStack.contains(where: { $0.id == video.id }) else {
                    print("📥 Preload canceled: video \(video.id) not in stack.")
                    return
                }
                
                // If still valid, create the item
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 2
                item.preferredPeakBitRate = 0
                
                await MainActor.run {
                    nextPlayer.replaceCurrentItem(with: item)
                    setupPlayerItem(item, isNext: true)
                    
                    // Start playing in background, volume=0
                    nextPlayer.seek(to: .zero) { _ in
                        self.nextPlayer.play()
                    }
                    print("✅ Next player ready with video: \(video.id)")
                }
            } catch {
                print("❌ Error preloading video: \(error.localizedDescription)")
            }
        }
    }
    
    func moveToNextVideo() {
        if let current = videoStack.first {
            markVideoAsSeen(current)
            videoStack.removeFirst()
            self.currentVideo = nil
        }
        
        // If empty after removal, unload everything
        if videoStack.isEmpty {
            print("📹 Video stack empty – unloading all videos.")
            unloadAllVideos()
            return
        }
        
        // Otherwise, ensure we have enough in the stack
        if videoStack.count < 3 {
            loadVideos()
        }
        
        // Set up the new current video
        if let nextVideo = videoStack.first {
            // Swap players/loopers
            let oldPlayer = currentPlayer
            let oldLooper = currentLooper
            
            currentPlayer = nextPlayer
            currentLooper = nextLooper
            
            nextPlayer = oldPlayer
            nextLooper = oldLooper
            
            currentPlayer.volume = 1
            nextPlayer.volume = 0
            
            self.currentVideo = nextVideo
            
            // Preload what's after that
            if let followingVideo = videoStack.dropFirst().first {
                preloadVideo(followingVideo)
            }
        }
    }
    
    /// Unload/stop playback entirely when no videos remain.
    private func unloadAllVideos() {
        print("📹 unloadAllVideos() - ensuring nothing is playing.")
        
        // Stop looping
        currentLooper?.disableLooping()
        nextLooper?.disableLooping()
        
        // Pause both
        currentPlayer.pause()
        nextPlayer.pause()
        
        // Remove all items from queue players
        currentPlayer.removeAllItems()
        nextPlayer.removeAllItems()
        
        // Clear their current items
        currentPlayer.replaceCurrentItem(with: nil)
        nextPlayer.replaceCurrentItem(with: nil)
        
        // Reset loopers
        currentLooper = nil
        nextLooper = nil
    }
    
    // Swipe handlers
    func handleRightSwipe() { moveToNextVideo() }
    func handleLeftSwipe()  { moveToNextVideo() }
    
    // Swipe up => share
    func handleUpSwipe() {
        if let currentItem = currentPlayer.currentItem,
           let urlAsset = currentItem.asset as? AVURLAsset,
           let currentVideo = videoStack.first {
            let shareText = "\(urlAsset.url)\n\n\(currentVideo.description)"
            itemsToShare = [shareText]
            isShowingShareSheet = true
        }
        moveToNextVideo()
    }
    
    // Swipe down => save
    func handleDownSwipe() {
        if let currentVideo = videoStack.first {
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
        // Clean up
        currentLooper?.disableLooping()
        nextLooper?.disableLooping()
        currentPlayer.pause()
        nextPlayer.pause()
    }
}