import SwiftUI
import AVKit
import UIKit

struct AutoplayVideoPlayer: UIViewControllerRepresentable {
    let player: AVQueuePlayer
    var shouldAutoplay: Bool = true
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .clear
        controller.contentOverlayView?.backgroundColor = .clear
        
        if let currentItem = player.currentItem {
            currentItem.preferredPeakBitRate = 0
            currentItem.preferredForwardBufferDuration = 2
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        
        if let currentItem = player.currentItem {
            currentItem.preferredPeakBitRate = 0
            currentItem.preferredForwardBufferDuration = 2
        }
        
        if shouldAutoplay {
            player.play()
        } else {
            player.pause()
        }
    }
    
    func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        // No extra teardown needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: AutoplayVideoPlayer
        init(_ parent: AutoplayVideoPlayer) {
            self.parent = parent
        }
    }
}