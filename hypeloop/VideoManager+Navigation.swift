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
        if videoStack.count < 3 {
            loadVideos()
        }
    }
    
    /// Swaps to the preloaded `nextPlayer` and sets its video as the current video.
    /// - Parameter autoPlay: Whether the new current player should start playing immediately.
    func swapToNextVideo(autoPlay: Bool = true) {
        if let nextVideo = videoStack.first {
            // Swap players and loopers
            let oldPlayer = currentPlayer
            let oldLooper = currentLooper
            
            currentPlayer = nextPlayer
            currentLooper = nextLooper
            
            nextPlayer = oldPlayer
            nextLooper = oldLooper
            
            // Set volumes accordingly
            currentPlayer.volume = 1
            nextPlayer.volume = 0
            
            currentVideo = nextVideo
            
            if autoPlay {
                currentPlayer.play()
            }
            
            // Preload the next video after the current one
            if let followingVideo = videoStack.dropFirst().first {
                preloadVideo(followingVideo)
            }
        }
    }
    
    /// Moves to the next video by preparing the next and swapping players.
    func moveToNextVideo() {
        prepareNextVideo()
        swapToNextVideo()
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