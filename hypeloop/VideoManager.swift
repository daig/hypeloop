//
//  VideoManager.swift
//  hypeloop
//

import SwiftUI
import AVKit
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth

class VideoManager: ObservableObject {
    // Marking setters as internal so that extension files can update them
    @Published internal(set) var videoStack: [VideoItem] = []
    @Published var currentPlayer: AVQueuePlayer
    @Published var nextPlayer: AVQueuePlayer
    @Published internal(set) var currentVideo: VideoItem?
    @Published var isShowingShareSheet = false
    @Published var itemsToShare: [Any]?
    @Published internal(set) var savedVideos: [VideoItem] = []
    @Published internal var isLoading = false
    @Published var isMuted = false
    
    // Player loopers for smooth video looping
    internal var currentLooper: AVPlayerLooper?
    internal var nextLooper: AVPlayerLooper?
    internal var seenVideosFilter: BloomFilterStore
    
    // Firestore instance
    internal let db = Firestore.firestore()
    
    // Document listener
    private var videoListener: ListenerRegistration?
    
    init() async {
        print("📹 Initializing VideoManager")
        // Initialize players and the bloom filter.
        currentPlayer = AVQueuePlayer()
        nextPlayer = AVQueuePlayer()
        seenVideosFilter = BloomFilterStore()
        
        // Configure nextPlayer to be muted initially
        nextPlayer.volume = 0
        
        // Configure audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
        
        // Wait for the bloom filter to load
        print("📹 Waiting for bloom filter to load...")
        let startTime = Date()
        while !seenVideosFilter.isLoaded {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            print("⏳ Waiting... elapsed: \(Int(-startTime.timeIntervalSinceNow))s")
        }
        print("📹 Bloom filter loaded after \(Int(-startTime.timeIntervalSinceNow))s")
        
        // Perform the initial video load
        print("📹 Starting initial video fetch")
        await loadVideos(initial: true)
        
        print("📹 VideoManager initialization complete")
    }
    
    func toggleMute() {
        isMuted.toggle()
        currentPlayer.volume = isMuted ? 0 : 1
    }
    
    deinit {
        // Clean up
        currentLooper?.disableLooping()
        nextLooper?.disableLooping()
        currentPlayer.pause()
        nextPlayer.pause()
    }
    
    @MainActor
    func reloadBloomFilterAndVideos() async {
        print("📹 Reloading bloom filter and videos")
        await seenVideosFilter.reloadFromFirebase()
        videoStack = []
        await loadVideos(initial: true)
    }
    
    func listenToVideoUpdates(videoId: String, completion: @escaping (VideoItem?) -> Void) {
        // Remove any existing listener
        videoListener?.remove()
        
        // Set up new listener
        videoListener = db.collection("videos").document(videoId)
            .addSnapshotListener { documentSnapshot, error in
                guard let document = documentSnapshot else {
                    print("Error fetching document: \(error?.localizedDescription ?? "Unknown error")")
                    completion(nil)
                    return
                }
                
                guard document.exists else {
                    print("Document does not exist")
                    completion(nil)
                    return
                }
                
                do {
                    let video = try document.data(as: VideoItem.self)
                    completion(video)
                } catch {
                    print("Error decoding video: \(error.localizedDescription)")
                    completion(nil)
                }
            }
    }
    
    // Clean up listener when no longer needed
    func removeVideoListener() {
        videoListener?.remove()
        videoListener = nil
    }
}
