import SwiftUI
import AVKit
import UIKit

// Custom VideoPlayer view that hides controls.
// Now accepts a flag so that the video can be shown statically.
struct AutoplayVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    var shouldAutoplay: Bool = true
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .clear
        controller.contentOverlayView?.backgroundColor = .clear
        
        // Enable HLS adaptive bitrate streaming
        if let currentItem = player.currentItem {
            currentItem.preferredPeakBitRate = 0 // Let AVPlayer choose the best bitrate
            currentItem.preferredForwardBufferDuration = 2 // Small buffer for quick start
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        
        // Update HLS settings for new player item
        if let currentItem = player.currentItem {
            currentItem.preferredPeakBitRate = 0
            currentItem.preferredForwardBufferDuration = 2
        }
        
        // Control playback based on shouldAutoplay flag
        if shouldAutoplay {
            player.play()
        } else {
            player.pause()
        }
    }
    
    func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        // Clean up any resources if needed
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

// ShareSheet wrapper for UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SwipeableVideoPlayer: View {
    @ObservedObject var videoManager: VideoManager
    @GestureState private var dragOffset: CGSize = .zero
    @State private var offset: CGSize = .zero
    @State private var showThumbsUp = false
    @State private var showThumbsDown = false
    @State private var showPaperAirplane = false
    @State private var showSaveIcon = false
    @State private var paperAirplaneOffset: CGFloat = 0
    @State private var saveIconOffset: CGFloat = 0
    @State private var isRefreshing = false
    
    // Constants for card animations
    private let swipeThreshold: CGFloat = 100
    private let maxRotation: Double = 35
    private let cardSpacing: CGFloat = 15
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Empty state with refresh button
                if videoManager.videoStack.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        
                        Text("You're all caught up!")
                            .foregroundColor(.white)
                            .font(.headline)
                        
                        Text("Check back later for new videos")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button(action: {
                            isRefreshing = true
                            Task {
                                await videoManager.loadVideos(initial: true)
                                // Set isRefreshing back to false after a short delay
                                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                                await MainActor.run {
                                    isRefreshing = false
                                }
                            }
                        }) {
                            Text("Tap to refresh")
                                .foregroundColor(.gray)
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                } else {
                    // Stack of cards:
                    // - Top card: current video (draggable)
                    // - Background card: next video (displayed statically)
                    ForEach((0..<min(2, videoManager.videoStack.count)), id: \.self) { index in
                        if index == 0 {
                            // Top card (current video)
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.black.opacity(0))
                                
                                AutoplayVideoPlayer(player: videoManager.currentPlayer)
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                                    .padding(.top, 60)
                                
                                // Overlay for author and description
                                VStack {
                                    Spacer()
                                    ZStack(alignment: .bottom) {
                                        LinearGradient(
                                            gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                                            startPoint: UnitPoint(x: 0.5, y: 0.3),
                                            endPoint: .bottom
                                        )
                                        
                                        if let currentVideo = videoManager.videoStack.first {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("@\(currentVideo.display_name)")
                                                    .font(.headline)
                                                    .bold()
                                                Text(currentVideo.description)
                                                    .font(.subheadline)
                                                    .lineLimit(2)
                                            }
                                            .foregroundColor(.white)
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.bottom, 80)
                                        }
                                    }
                                    .frame(height: geometry.size.height / 2)
                                }
                            }
                            .frame(width: geometry.size.width - cardSpacing * 2,
                                   height: geometry.size.height - cardSpacing * 2)
                            .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                            .rotationEffect(.degrees(rotationAngle))
                            .gesture(
                                DragGesture()
                                    .updating($dragOffset) { value, state, _ in
                                        state = value.translation
                                    }
                                    .onEnded(onDragEnded)
                            )
                            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: dragOffset)
                            .zIndex(2)
                        } else {
                            // Background card (next video)
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.black)
                                
                                AutoplayVideoPlayer(player: videoManager.nextPlayer)
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                                    .padding(.top, 60)
                                
                                // Add the same overlay gradient as the top card for visual consistency
                                VStack {
                                    Spacer()
                                    LinearGradient(
                                        gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                                        startPoint: UnitPoint(x: 0.5, y: 0.3),
                                        endPoint: .bottom
                                    )
                                    .frame(height: geometry.size.height / 2)
                                }
                            }
                            .frame(width: geometry.size.width - cardSpacing * 2,
                                   height: geometry.size.height - cardSpacing * 2)
                            .zIndex(1)
                        }
                    }
                    
                    // Paper airplane overlay
                    Image(systemName: "paperplane.fill")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.blue)
                        .opacity(showPaperAirplane ? 0.8 : 0)
                        .scaleEffect(showPaperAirplane ? 1 : 0.5)
                        .rotationEffect(.degrees(-45))
                        .offset(y: paperAirplaneOffset)
                        .animation(.spring(response: 0.3).speed(0.7), value: showPaperAirplane)
                        .animation(.interpolatingSpring(stiffness: 40, damping: 8), value: paperAirplaneOffset)
                        .zIndex(3)
                    
                    // Thumbs up overlay
                    Image(systemName: "hand.thumbsup.fill")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.green)
                        .opacity(showThumbsUp ? 0.8 : 0)
                        .scaleEffect(showThumbsUp ? 1 : 0.5)
                        .animation(.spring(response: 0.3), value: showThumbsUp)
                        .zIndex(3)
                    
                    // Thumbs down overlay
                    Image(systemName: "hand.thumbsdown.fill")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.red)
                        .opacity(showThumbsDown ? 0.8 : 0)
                        .scaleEffect(showThumbsDown ? 1 : 0.5)
                        .animation(.spring(response: 0.3), value: showThumbsDown)
                        .zIndex(3)
                    
                    // Save icon overlay
                    Image(systemName: "square.and.arrow.down.fill")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.purple)
                        .opacity(showSaveIcon ? 0.8 : 0)
                        .scaleEffect(showSaveIcon ? 1 : 0.5)
                        .offset(y: saveIconOffset)
                        .animation(.spring(response: 0.3).speed(0.7), value: showSaveIcon)
                        .animation(.interpolatingSpring(stiffness: 40, damping: 8), value: saveIconOffset)
                        .zIndex(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                videoManager.currentPlayer.play()
            }
            .onDisappear {
                videoManager.currentPlayer.pause()
            }
            .sheet(isPresented: $videoManager.isShowingShareSheet) {
                if let items = videoManager.itemsToShare {
                    ShareSheet(items: items)
                }
            }
        }
    }
    
    // Calculate rotation based on drag offset.
    private var rotationAngle: Double {
        let dragPercentage = Double(dragOffset.width + offset.width) / 300
        return dragPercentage * maxRotation
    }
    
    // Handle drag gesture end.
    private func onDragEnded(_ gesture: DragGesture.Value) {
        let dragWidth = gesture.translation.width
        let dragHeight = gesture.translation.height
        
        // Vertical swipes.
        if abs(dragHeight) > swipeThreshold && abs(dragHeight) > abs(dragWidth) {
            if dragHeight < 0 {
                // Swipe up: trigger share action.
                showPaperAirplane = true
                withAnimation(.easeOut(duration: 0.3)) {
                    offset.height = -500
                    paperAirplaneOffset = -200
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    videoManager.handleUpSwipe()
                    withAnimation(.none) { offset = .zero }
                    withAnimation(.easeOut(duration: 0.2)) { showPaperAirplane = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        paperAirplaneOffset = 0
                    }
                }
            } else {
                // Swipe down: trigger save action.
                showSaveIcon = true
                saveIconOffset = 0
                withAnimation(.easeOut(duration: 0.3)) {
                    offset.height = 500
                    saveIconOffset = 200
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    videoManager.handleDownSwipe()
                    withAnimation(.none) { offset = .zero }
                    withAnimation(.easeOut(duration: 0.2)) { showSaveIcon = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        saveIconOffset = 0
                    }
                }
            }
        }
        // Horizontal swipes.
        else if abs(dragWidth) > swipeThreshold && abs(dragWidth) > abs(dragHeight) {
            let direction: CGFloat = dragWidth > 0 ? 1 : -1
            if direction > 0 {
                showThumbsUp = true
            } else {
                showThumbsDown = true
            }
            withAnimation(.easeOut(duration: 0.3)) {
                offset.width = direction * 500
                offset.height = gesture.translation.height
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if direction > 0 {
                    videoManager.handleRightSwipe()
                } else {
                    videoManager.handleLeftSwipe()
                }
                withAnimation(.none) { offset = .zero }
                withAnimation(.easeOut(duration: 0.2)) {
                    showThumbsUp = false
                    showThumbsDown = false
                }
            }
        } else {
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.6)) {
                offset = .zero
            }
        }
    }
}