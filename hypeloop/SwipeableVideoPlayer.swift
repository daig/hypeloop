import SwiftUI
import AVKit
import UIKit

// Custom VideoPlayer view that hides controls
struct AutoplayVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
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
            currentItem.preferredForwardBufferDuration = 5 // Buffer 5 seconds ahead
        }
        
        // Set up looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        
        // Update HLS settings for new player item
        if let currentItem = player.currentItem {
            currentItem.preferredPeakBitRate = 0
            currentItem.preferredForwardBufferDuration = 5
        }
        
        // Update looping observer for new player item
        NotificationCenter.default.removeObserver(context.coordinator)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        // Remove observer when view is dismantled
        NotificationCenter.default.removeObserver(coordinator)
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
    private let secondCardScale: CGFloat = 0.95
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Empty state with refresh button
                if videoManager.videoStack.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        
                        Text("Up to date!")
                            .foregroundColor(.white)
                            .font(.headline)
                        
                        Button(action: {
                            isRefreshing = true
                            videoManager.loadVideosFromMux(initial: true)
                            // Set isRefreshing back to false after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                isRefreshing = false
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
                    // Stack of cards
                    ForEach((0..<min(2, videoManager.videoStack.count)), id: \.self) { index in
                        if index == 0 {
                            // Top card (current video)
                            ZStack {
                                // Background for the card
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.black)
                                
                                // Video player
                                AutoplayVideoPlayer(player: videoManager.currentPlayer)
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                                    .padding(.top, 60)
                                
                                // Author and description overlay
                                VStack {
                                    Spacer()
                                    // Gradient background for bottom half of card
                                    ZStack(alignment: .bottom) {
                                        LinearGradient(
                                            gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                                            startPoint: UnitPoint(x: 0.5, y: 0.3),
                                            endPoint: .bottom
                                        )
                                        
                                        // Text content
                                        if let currentVideo = videoManager.videoStack.first {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("@\(currentVideo.creator)")
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
                            .frame(width: geometry.size.width - cardSpacing * 2, height: geometry.size.height - cardSpacing * 2)
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
                            // Background card (black)
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.black)
                            }
                            .frame(width: geometry.size.width - cardSpacing * 2, height: geometry.size.height - cardSpacing * 2)
                            .cornerRadius(20)
                            .scaleEffect(
                                min(
                                    secondCardScale + (1 - secondCardScale) * abs(offset.width) / geometry.size.width,
                                    1.0
                                )
                            )
                            .offset(y: cardSpacing)
                            .zIndex(1)
                        }
                    }
                    
                    // Paper airplane overlay (moved outside card stack)
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
    
    // Calculate rotation based on drag
    private var rotationAngle: Double {
        let maxAngle = maxRotation
        let dragPercentage = Double(dragOffset.width + offset.width) / 300
        return dragPercentage * maxAngle
    }
    
    // Handle drag gesture end
    private func onDragEnded(_ gesture: DragGesture.Value) {
        let dragThreshold = swipeThreshold
        let dragWidth = gesture.translation.width
        let dragHeight = gesture.translation.height
        
        // Check for vertical swipes first
        if abs(dragHeight) > dragThreshold && abs(dragHeight) > abs(dragWidth) {
            if dragHeight < 0 {
                // Swipe up - show paper airplane first
                showPaperAirplane = true
                
                // Animate card and paper airplane together
                withAnimation(.easeOut(duration: 0.3)) {
                    offset.height = -500
                    paperAirplaneOffset = -200
                }
                
                // After animation completes, trigger share and reset
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Trigger share sheet
                    videoManager.handleUpSwipe()
                    
                    // Reset card position
                    withAnimation(.none) {
                        offset = .zero
                    }
                    
                    // Fade out paper airplane
                    withAnimation(.easeOut(duration: 0.2)) {
                        showPaperAirplane = false
                    }
                    
                    // Reset paper airplane position without animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        paperAirplaneOffset = 0
                    }
                }
            } else {
                // Swipe down - show save icon first
                showSaveIcon = true
                saveIconOffset = 0 // Reset position
                
                // Animate card and save icon together
                withAnimation(.easeOut(duration: 0.3)) {
                    offset.height = 500
                    saveIconOffset = 200
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    videoManager.handleDownSwipe()
                    
                    // Reset card position
                    withAnimation(.none) {
                        offset = .zero
                    }
                    
                    // Fade out save icon
                    withAnimation(.easeOut(duration: 0.2)) {
                        showSaveIcon = false
                    }
                    
                    // Reset save icon position without animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        saveIconOffset = 0
                    }
                }
            }
        }
        // Horizontal swipes
        else if abs(dragWidth) > dragThreshold && abs(dragWidth) > abs(dragHeight) {
            let direction: CGFloat = dragWidth > 0 ? 1 : -1
            
            // Show appropriate thumb indicator immediately
            if direction > 0 {
                showThumbsUp = true
            } else {
                showThumbsDown = true
            }
            
            // Animate card
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
                
                // Reset card position
                withAnimation(.none) {
                    offset = .zero
                }
                
                // Fade out indicators
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

#Preview {
    SwipeableVideoPlayer(videoManager: VideoManager())
}
