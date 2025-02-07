//
//  VideoManager+SwipeHandlers.swift
//  hypeloop
//

import SwiftUI
import AVKit

extension VideoManager {
    
    // MARK: - Swipe Handlers
    
    func handleRightSwipe() {
        moveToNextVideo()
    }
    
    func handleLeftSwipe() {
        moveToNextVideo()
    }
    
    // Swipe up => share
    func handleUpSwipe() {
        if let currentItem = currentPlayer.currentItem,
           let urlAsset = currentItem.asset as? AVURLAsset,
           let currentVideo = videoStack.first {
            let shareText = "\(urlAsset.url)\n\n\(currentVideo.description)"
            itemsToShare = [shareText]
            prepareNextVideo()
            swapToNextVideo(autoPlay: false)
            isShowingShareSheet = true
        }
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
}