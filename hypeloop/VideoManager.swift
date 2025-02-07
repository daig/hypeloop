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
        // Initialize players and the bloom filter.
        currentPlayer = AVPlayer()
        nextPlayer = AVPlayer()
        seenVideosFilter = BloomFilterStore()
        
        // Configure nextPlayer to be muted.
        nextPlayer.volume = 0
        
        // Wait for the bloom filter to load.
        print("📹 Waiting for bloom filter to load...")
        let startTime = Date()
        while !seenVideosFilter.isLoaded {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            print("⏳ Waiting for bloom filter to load... Time elapsed: \(Int(-startTime.timeIntervalSinceNow))s")
        }
        print("📹 Bloom filter loaded after \(Int(-startTime.timeIntervalSinceNow))s")
        
        // Perform the initial video load.
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
                print("📹 Skipping video load - stack not empty")
                return
            }
            
            isLoading = true
            
            do {
                print("📡 Fetching videos from Firestore...")
                let allVideos = try await db.collection("videos").getDocuments()
                print("📊 Debug: Found \(allVideos.documents.count) total videos in Firestore")
                print("📊 Debug: Video statuses: \(allVideos.documents.map { $0.data()["status"] as? String ?? "unknown" })")
                
                let snapshot = try await db.collection("videos")
                    .whereField("status", isEqualTo: "ready")
                    .order(by: "created_at", descending: true)
                    .limit(to: 50)
                    .getDocuments()
                
                print("📹 Starting video processing")
                let startTime = Date()
                while !seenVideosFilter.isLoaded {
                    print("⏳ Waiting for bloom filter to load... Time elapsed: \(Int(-startTime.timeIntervalSinceNow))s")
                    try await Task.sleep(nanoseconds: 100_000_000)
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
                let unseenVideos = newVideos.filter { video in
                    let isSeen = self.seenVideosFilter.mightContain(video.id)
                    if isSeen { seenCount += 1 }
                    print("📹 Video \(video.id): seen=\(isSeen)")
                    return !isSeen
                }
                
                print("📹 Filtering complete - Total: \(newVideos.count), Seen: \(seenCount), Unseen: \(unseenVideos.count)")
                allVideosSeen = unseenVideos.isEmpty && !newVideos.isEmpty
                
                videoStack.append(contentsOf: unseenVideos)
                
                if initial && !videoStack.isEmpty {
                    let firstVideo = videoStack[0]
                    let item = AVPlayerItem(url: firstVideo.playbackUrl)
                    currentPlayer.replaceCurrentItem(with: item)
                    setupPlayerItem(item)
                    currentVideo = firstVideo
                    currentPlayer.play()
                    
                    // Preload the next video if available.
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
    
    private func setupPlayerItem(_ item: AVPlayerItem, isNext: Bool = false) {
        item.preferredForwardBufferDuration = 2  // Buffer 2 seconds for quick start
        item.preferredPeakBitRate = 0  // Let system determine best bitrate
        
        let player = isNext ? nextPlayer : currentPlayer
        
        // Remove existing observer
        let existingObserver = isNext ? nextItemObserver : currentItemObserver
        if let observer = existingObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Add new observer
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            player.seek(to: .zero) { _ in
                player.play()
            }
        }
        
        // Store observer reference
        if isNext {
            nextItemObserver = observer
        } else {
            currentItemObserver = observer
        }
    }
    
    private func preloadVideo(_ video: VideoItem) {
        print("📥 Preloading video: \(video.id)")
        
        let resourceOptions: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        let asset = AVURLAsset(url: video.playbackUrl, options: resourceOptions)
        
        Task {
            do {
                try await asset.load(.isPlayable, .duration)
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 2  // Small buffer for quick start
                item.preferredPeakBitRate = 0  // Let system determine best bitrate
                
                await MainActor.run {
                    nextPlayer.replaceCurrentItem(with: item)
                    setupPlayerItem(item, isNext: true)
                    
                    // Start playing the video muted in the background
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
        if let currentVideo = videoStack.first {
            markVideoAsSeen(currentVideo)
            videoStack.removeFirst()
            self.currentVideo = nil
        }
        
        if videoStack.count < 3 {
            loadVideos()
        }
        
        if videoStack.isEmpty {
            print("📹 Video stack empty - waiting for manual reload")
            return
        }
        
        if let nextVideo = videoStack.first {
            // Swap the players.
            let oldPlayer = currentPlayer
            currentPlayer = nextPlayer
            nextPlayer = oldPlayer
            
            // Ensure the current player's item is properly set up for looping
            if let currentItem = currentPlayer.currentItem {
                setupPlayerItem(currentItem)
            }
            
            // Update volumes and ensure playback
            currentPlayer.volume = 1
            currentPlayer.seek(to: .zero) { _ in
                self.currentPlayer.play()
            }
            nextPlayer.volume = 0
            
            self.currentVideo = nextVideo
            
            // Preload the following video if available.
            if let followingVideo = videoStack.dropFirst().first {
                preloadVideo(followingVideo)
            }
        }
    }
    
    func handleRightSwipe() {
        moveToNextVideo()
    }
    
    func handleLeftSwipe() {
        moveToNextVideo()
    }
    
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
        if let observer = currentItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = nextItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        currentPlayer.pause()
        nextPlayer.pause()
    }
}