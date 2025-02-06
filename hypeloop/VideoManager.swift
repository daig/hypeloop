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
    @Published private(set) var currentVideo: VideoItem?
    @Published var isShowingShareSheet = false
    @Published var itemsToShare: [Any]?
    @Published private(set) var savedVideos: [VideoItem] = []
    @Published private var isLoading = false
    @Published private(set) var allVideosSeen = false
    
    private var preloadedItem: AVPlayerItem?
    private var preloadedAsset: AVAsset?
    private var playerItemObserver: NSObjectProtocol?
    private var seenVideosFilter: BloomFilter
    private let userDefaults = UserDefaults.standard
    private static let BLOOM_FILTER_KEY = "seen_videos_bloom_filter"
    private var videosListener: ListenerRegistration?
    
    // Firestore instance
    private let db = Firestore.firestore()
    
    init() {
        // Initialize with a dummy AVPlayer
        currentPlayer = AVPlayer()
        
        // Initialize or load bloom filter
        if let filterData = userDefaults.data(forKey: VideoManager.BLOOM_FILTER_KEY) {
            seenVideosFilter = BloomFilter.deserialize(filterData)
        } else {
            seenVideosFilter = BloomFilter()
        }
        
        // Set up real-time listener for new videos
        // Initial load will be handled by the listener
        setupVideosListener()
    }
    
    private func setupVideosListener() {
        videosListener = db.collection("videos")
            .whereField("status", isEqualTo: "ready")
            .order(by: "created_at", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error listening for video updates: \(error.localizedDescription)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let newVideos = snapshot.documents.compactMap { document -> VideoItem? in
                    do {
                        return try document.data(as: VideoItem.self)
                    } catch {
                        print("Error decoding video: \(error.localizedDescription)")
                        return nil
                    }
                }
                
                // Filter out videos we've already seen using bloom filter
                let unseenVideos = newVideos.filter { !self.seenVideosFilter.mightContain($0.id) }
                
                // Update the video stack
                Task { @MainActor in
                    print("📹 Listener received \(unseenVideos.count) unseen videos out of \(newVideos.count) total")
                    
                    // Always filter and only append unseen videos
                    if !unseenVideos.isEmpty {
                        // If we already have videos in the stack, just append new ones
                        if !self.videoStack.isEmpty {
                            self.videoStack.append(contentsOf: unseenVideos)
                        } else {
                            // This is our first load, set up the first video
                            self.videoStack = unseenVideos
                            self.setupVideo(unseenVideos[0])
                            self.markVideoAsSeen(unseenVideos[0])
                            
                            // Preload the next video if available
                            if unseenVideos.count > 1 {
                                self.preloadVideo(unseenVideos[1])
                            }
                        }
                    } else {
                        print("📹 No new unseen videos from listener")
                    }
                    
                    // Update allVideosSeen status
                    self.allVideosSeen = unseenVideos.isEmpty && !newVideos.isEmpty
                }
            }
    }
    
    private func markVideoAsSeen(_ video: VideoItem) {
        print("📹 Marking video as seen: \(video.id)")
        seenVideosFilter.add(video.id)
        
        // Save to UserDefaults
        let filterData = seenVideosFilter.serialize()
        userDefaults.set(filterData, forKey: VideoManager.BLOOM_FILTER_KEY)
        
        // Optionally sync with Firestore for cross-device support
        Task {
            do {
                try await db.collection("users").document(Auth.auth().currentUser?.uid ?? "").collection("seen_videos").document(video.id).setData([
                    "timestamp": FieldValue.serverTimestamp()
                ])
            } catch {
                print("Error syncing seen video to Firestore: \(error)")
            }
        }
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
                
                let newVideos = snapshot.documents.compactMap { document -> VideoItem? in
                    do {
                        return try document.data(as: VideoItem.self)
                    } catch {
                        print("❌ Error decoding video: \(error.localizedDescription)")
                        print("📄 Document data: \(document.data())")
                        return nil
                    }
                }
                
                print("✅ Received \(newVideos.count) ready videos")
                
                print("📹 Processing \(newVideos.count) videos for filtering")
                // Filter out videos we've already seen
                let unseenVideos = newVideos.filter { video in
                    let isSeen = self.seenVideosFilter.mightContain(video.id)
                    print("📹 Video \(video.id): seen=\(isSeen)")
                    return !isSeen
                }
                
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
    
    private func setupVideo(_ video: VideoItem) {
        print("🎬 Setting up video: \(video.id)")
        
        // Create AVPlayerItem for the video
        let playerItem = AVPlayerItem(url: video.playbackUrl)
        
        // Configure the player item
        playerItem.preferredForwardBufferDuration = 5  // Buffer 5 seconds ahead
        
        // Replace the current item and set up observers
        currentPlayer.replaceCurrentItem(with: playerItem)
        setupPlayerItem(playerItem)
        
        // Update current video
        currentVideo = video
        
        // Start playing
        currentPlayer.play()
        
        // Start preloading the next video
        if let nextVideo = videoStack.dropFirst().first {
            preloadVideo(nextVideo)
        }
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
                    // Only store the preloaded item if we're still preloading the same asset
                    if asset === preloadedAsset {
                        print("✅ Preload complete for video: \(video.id)")
                        self.preloadedItem = item
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
        videosListener?.remove()  // Clean up Firestore listener
    }
} 