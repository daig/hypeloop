import Foundation
import SwiftUI
import AVKit

class VideoManager: ObservableObject {
    // Sample video URLs with more variety
    private let availableVideos = [
        // Nature and landscapes
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8",
        // Tech demo
        "https://bitdash-a.akamaihd.net/content/MI201109210084_1/m3u8s/f08e80da-bf1d-4e3d-8899-f0f6155f6efa.m3u8",
        // Sports
        "https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8",
        // Animation
        "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
        // Urban scenes
        "https://cdn.bitmovin.com/content/assets/art-of-motion-dash-hls-progressive/m3u8s/f08e80da-bf1d-4e3d-8899-f0f6155f6efa.m3u8",
        // Nature documentary
        "https://test-streams.mux.dev/test_001/stream.m3u8",
        // Space footage
        "https://cph-p2p-msl.akamaized.net/hls/live/2000341/test/master.m3u8",
        // Ocean scenes
        "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8",
    ].map { URL(string: $0)! }
    
    @Published var history: [URL] = []
    @Published var currentVideoIndex: Int = 0
    @Published var currentPlayer: AVPlayer?
    
    init() {
        let initialVideo = availableVideos[0]
        history.append(initialVideo)
        currentPlayer = AVPlayer(url: initialVideo)
    }
    
    private func cleanupCurrentVideo() {
        currentPlayer?.pause()
        currentPlayer?.replaceCurrentItem(with: nil)
        currentPlayer = nil
    }
    
    func getNextVideo() -> URL? {
        let unwatchedVideos = availableVideos.filter { !history.contains($0) }
        guard !unwatchedVideos.isEmpty else { 
            // If we've watched all videos, start over with a random one
            return availableVideos.randomElement() 
        }
        return unwatchedVideos.randomElement()
    }
    
    func goToNextVideo() {
        guard let nextVideo = getNextVideo() else { return }
        cleanupCurrentVideo()
        
        // If we're not at the end of history, remove all videos after current index
        if currentVideoIndex < history.count - 1 {
            history.removeSubrange((currentVideoIndex + 1)...)
        }
        
        history.append(nextVideo)
        currentVideoIndex = history.count - 1
        currentPlayer = AVPlayer(url: nextVideo)
        currentPlayer?.play()
    }
    
    func goToPreviousVideo() {
        guard currentVideoIndex > 0 else { return }
        cleanupCurrentVideo()
        currentVideoIndex -= 1
        let previousVideo = history[currentVideoIndex]
        currentPlayer = AVPlayer(url: previousVideo)
        currentPlayer?.play()
    }
    
    deinit {
        cleanupCurrentVideo()
    }
} 