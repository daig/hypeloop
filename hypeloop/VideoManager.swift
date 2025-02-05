import Foundation
import SwiftUI
import AVKit
import FirebaseStorage

struct VideoItem: Identifiable {
    let id: String
    let url: URL
    let creator: String
    let description: String
    let updatedTime: Date
    
    init(id: String, url: URL, creator: String = "User", description: String = "", updatedTime: Date = Date()) {
        self.id = id
        self.url = url
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
    
    init() {
        // Initialize with a dummy AVPlayer
        currentPlayer = AVPlayer()
        
        // Load videos from Firebase
        Task {
            await loadVideosFromFirebase(initial: true)
        }
    }
    
    func loadVideosFromFirebase(initial: Bool = false) async {
        print("🌐 Starting Firebase video list fetch...")
        guard !isLoading else {
            print("⚠️ Skipping fetch - already loading")
            return
        }
        isLoading = true
        defer { isLoading = false }
        
        let storageRef = Storage.storage().reference()
        let videosRef = storageRef.child("videos")
        
        do {
            let result = try await videosRef.listAll()
            print("📋 Found \(result.items.count) videos in Firebase")
            var newVideos: [VideoItem] = []
            var totalDataSize: Int64 = 0
            
            for item in result.items {
                if !initial && seenVideoIds.contains(item.name) {
                    print("⏭️ Skipping \(item.name) - already seen")
                    continue
                }
                
                do {
                    print("📥 Fetching metadata for video: \(item.name)")
                    let metadata = try await item.getMetadata()
                    let size = metadata.size
                    totalDataSize += size
                    
                    print("🔗 Getting download URL for video: \(item.name) (Size: \(formatFileSize(size)))")
                    let url = try await item.downloadURL()
                    
                    let video = VideoItem(
                        id: item.name,
                        url: url,
                        creator: metadata.customMetadata?["creator"] ?? "User",
                        description: metadata.customMetadata?["description"] ?? "A cool video",
                        updatedTime: metadata.updated ?? Date()
                    )
                    newVideos.append(video)
                    print("✅ Successfully loaded video: \(item.name)")
                } catch {
                    print("❌ Error loading video \(item.name): \(error.localizedDescription)")
                    continue
                }
            }
            
            print("📊 Network usage summary:")
            print("- Total videos loaded: \(newVideos.count)")
            print("- Total metadata size: \(formatFileSize(totalDataSize))")
            
            // Sort by most recent
            newVideos.sort(by: { $0.updatedTime > $1.updatedTime })
            
            await MainActor.run {
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
        } catch {
            print("❌ Error loading videos from Firebase: \(error.localizedDescription)")
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
            Task {
                await loadVideosFromFirebase()
            }
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