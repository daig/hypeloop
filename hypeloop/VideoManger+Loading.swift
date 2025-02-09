//
//  VideoManager+Loading.swift
//  hypeloop
//

import SwiftUI
import FirebaseFirestore
import AVKit

extension VideoManager {
    
    /// Fetches videos from Firestore that are marked as ready
    /// - Returns: Array of VideoItem objects
    private func fetchReadyVideosFromFirestore() async throws -> [VideoItem] {
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
        
        // Decode all snapshots
        return snapshot.documents.compactMap { document -> VideoItem? in
            do {
                let video = try document.data(as: VideoItem.self)
                print("📹 Decoded video: \(video.id)")
                return video
            } catch {
                print("❌ Error decoding video: \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    /// Fetches and filters videos using a provided async function
    /// - Parameter fetchFunction: An async function that returns an array of VideoItems
    /// - Returns: A tuple containing filtered videos and whether all videos were seen
    private func fetchUnseenVideos(using fetchFunction: () async throws -> [VideoItem]) async throws -> [VideoItem] {
        let startTime = Date()
        while !seenVideosFilter.isLoaded {
            print("⏳ Waiting for bloom filter... elapsed: \(Int(-startTime.timeIntervalSinceNow))s")
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        let newVideos = try await fetchFunction()
        print("✅ Received \(newVideos.count) ready videos")
        
        let unseenVideos = newVideos.filter { video in !self.seenVideosFilter.mightContain(video.id) }
        
        print("📹 Filtered videos: total \(newVideos.count), unseen \(unseenVideos.count)")
        
        return unseenVideos
    }
    
    /// Loads videos from Firestore, filtering out those already seen.
    /// - Parameter initial: Indicates if this is the first load after initialization.
    func loadVideos(initial: Bool = false) {
        Task { @MainActor in
            if !initial && !videoStack.isEmpty {
                print("📹 Skipping load – stack not empty")
                return
            }
            
            isLoading = true
            
            do {
                let unseenVideos = try await fetchUnseenVideos { 
                    try await fetchReadyVideosFromFirestore() 
                }
                
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
    
    /// Marks the specified video as seen by adding its ID to the bloom filter.
    func markVideoAsSeen(_ video: VideoItem) {
        print("📹 Marking video as seen: \(video.id)")
        seenVideosFilter.add(video.id)
    }
}
