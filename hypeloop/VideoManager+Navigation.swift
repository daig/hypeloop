//
//  VideoManager+Navigation.swift
//  hypeloop
//

import SwiftUI
import AVKit

extension VideoManager {
    
    /// Prepares the next video by marking the current one as seen and removing it from the stack.
    func prepareNextVideo() {
        if let current = videoStack.first {
            markVideoAsSeen(current)
            videoStack.removeFirst()
            currentVideo = nil
        }
        
        // If empty after removal, unload everything
        if videoStack.isEmpty {
            print("📹 Video stack empty – unloading all videos.")
            unloadAllVideos()
            return
        }
        
        // Otherwise, ensure we have enough in the stack
        if videoStack.count < 3 { loadVideos() }
    }
    
    /// Swaps to the preloaded `nextPlayer` and sets its video as the current video.
    /// - Parameter autoPlay: Whether the new current player should start playing immediately.
    func swapToNextVideo(autoPlay: Bool = true) {
        if let nextVideo = videoStack.first {
            // Keep the current player playing during transition
            let oldPlayer = currentPlayer
            let oldLooper = currentLooper
            
            // Set up the next player first
            currentPlayer = nextPlayer
            currentLooper = nextLooper
            
            // Set volumes according to mute state
            currentPlayer.volume = isMuted ? 0 : 1
            
            // Update the current video
            currentVideo = nextVideo
            
            if autoPlay {
                currentPlayer.play()
            }
            
            // Set up next player immediately since we know it's ready
            Task { @MainActor in
                // Now safely set up the next player
                self.nextPlayer = oldPlayer
                self.nextLooper = oldLooper
                self.nextPlayer.volume = 0
                
                // Preload the next video after the current one
                if let followingVideo = self.videoStack.dropFirst().first {
                    self.preloadVideo(followingVideo)
                }
            }
        }
    }
    
    /// Moves to the next video by preparing the next and swapping players.
    /// - Parameter autoPlay: Whether the new current player should start playing immediately.
    func moveToNextVideo(autoPlay: Bool = true) {
        prepareNextVideo()
        swapToNextVideo(autoPlay: autoPlay)
    }
    
    /// Unloads all videos and stops playback.
    func unloadAllVideos() {
        print("📹 unloadAllVideos() - ensuring nothing is playing.")
        
        // Stop looping
        currentLooper?.disableLooping()
        nextLooper?.disableLooping()
        
        // Pause both players
        currentPlayer.pause()
        nextPlayer.pause()
        
        // Remove all items from both players
        currentPlayer.removeAllItems()
        nextPlayer.removeAllItems()
        
        // Clear their current items
        currentPlayer.replaceCurrentItem(with: nil)
        nextPlayer.replaceCurrentItem(with: nil)
        
        // Reset loopers
        currentLooper = nil
        nextLooper = nil
    }
}
