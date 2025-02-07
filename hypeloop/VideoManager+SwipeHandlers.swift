//
//  VideoManager+SwipeHandlers.swift
//  hypeloop
//

import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseAuth

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
        guard let currentVideo = videoStack.first,
              let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                let db = Firestore.firestore()
                let savedVideoRef = db.collection("users").document(userId)
                    .collection("saved_videos").document(currentVideo.id)
                
                // Check if already saved
                let doc = try await savedVideoRef.getDocument()
                if !doc.exists {
                    // Save video data
                    try await savedVideoRef.setData([
                        "id": currentVideo.id,
                        "playback_id": currentVideo.playback_id,
                        "creator": currentVideo.creator,
                        "display_name": currentVideo.display_name,
                        "description": currentVideo.description,
                        "created_at": currentVideo.created_at,
                        "saved_at": Int(Date().timeIntervalSince1970 * 1000)
                    ])
                    
                    // Update local state
                    if !savedVideos.contains(where: { $0.id == currentVideo.id }) {
                        savedVideos.append(currentVideo)
                    }
                }
            } catch {
                print("Error saving video: \(error.localizedDescription)")
            }
        }
        moveToNextVideo()
    }
    
    func removeSavedVideo(at indexSet: IndexSet) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        
        for index in indexSet {
            let video = savedVideos[index]
            Task {
                do {
                    // Remove from Firestore
                    try await db.collection("users").document(userId)
                        .collection("saved_videos").document(video.id).delete()
                    
                    // Update local state
                    await MainActor.run {
                        savedVideos.remove(at: index)
                    }
                } catch {
                    print("Error removing saved video: \(error.localizedDescription)")
                }
            }
        }
    }
}