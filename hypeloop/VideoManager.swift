import Foundation
import SwiftUI
import AVKit
import FirebaseFunctions
import FirebaseFirestore

struct VideoItem: Codable {
    let id: String
    let playback_id: String
    let creator: String
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
    
    private var preloadedItem: AVPlayerItem?
    private var preloadedAsset: AVAsset?
    private var playerItemObserver: NSObjectProtocol?
    private var seenVideoIds: Set<String> = []  // Track seen videos
    private var videosListener: ListenerRegistration?
    
    // Firestore instance
    private let db = Firestore.firestore()
    
    init() {
        // Initialize with a dummy AVPlayer
        currentPlayer = AVPlayer()
        
        // Load videos
        loadVideos(initial: true)
        
        // Set up real-time listener for new videos
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
                
                // Filter out videos we've already seen
                let unseenVideos = newVideos.filter { !self.seenVideoIds.contains($0.id) }
                
                // Update the video stack
                Task { @MainActor in
                    // If this is our first load and we have no videos, set up the first video
                    if self.videoStack.isEmpty && !newVideos.isEmpty {
                        self.videoStack = newVideos
                        self.setupVideo(newVideos[0])
                    } else {
                        // Otherwise, just append new unseen videos
                        self.videoStack.append(contentsOf: unseenVideos)
                    }
                    
                    // Preload the next video if available
                    if let nextVideo = self.videoStack.dropFirst().first {
                        self.preloadVideo(nextVideo)
                    }
                }
            }
    }
    
    func loadVideos(initial: Bool = false) {
        Task { @MainActor in
            // If not initial load and we already have videos, don't reload
            guard initial || videoStack.isEmpty else { return }
            
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
                
                // Filter out videos we've already seen
                let unseenVideos = newVideos.filter { !seenVideoIds.contains($0.id) }
                
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
            seenVideoIds.insert(currentVideo.id)
            videoStack.removeFirst()
        }
        
        // If stack is getting low, load more videos
        if videoStack.count < 3 {
            loadVideos()
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