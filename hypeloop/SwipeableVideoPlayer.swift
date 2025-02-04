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
        controller.videoGravity = .resizeAspect  // Changed to resizeAspect for proper scaling
        
        // Configure the view to be centered
        controller.view.backgroundColor = .clear
        controller.contentOverlayView?.backgroundColor = .clear
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

struct SwipeableVideoPlayer: View {
    @StateObject private var videoManager = VideoManager()
    @GestureState private var dragOffset: CGSize = .zero
    @State private var offset: CGSize = .zero
    @State private var hasStartedPreloading = false
    @State private var showThumbsUp = false
    @State private var showThumbsDown = false
    @State private var showPaperAirplane = false
    @State private var showSaveIcon = false
    @State private var paperAirplaneOffset: CGFloat = 0
    @State private var saveIconOffset: CGFloat = 0
    
    // Constants for card animations
    private let swipeThreshold: CGFloat = 100
    private let maxRotation: Double = 35
    private let cardSpacing: CGFloat = 15
    private let secondCardScale: CGFloat = 0.95
    private let preloadThreshold: CGFloat = 50
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
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
                                .overlay(
                                    ZStack {
                                        // Thumbs up overlay
                                        Image(systemName: "hand.thumbsup.fill")
                                            .resizable()
                                            .frame(width: 100, height: 100)
                                            .foregroundColor(.green)
                                            .opacity(showThumbsUp ? 0.8 : 0)
                                            .scaleEffect(showThumbsUp ? 1 : 0.5)
                                            .animation(.spring(response: 0.3), value: showThumbsUp)
                                        
                                        // Thumbs down overlay
                                        Image(systemName: "hand.thumbsdown.fill")
                                            .resizable()
                                            .frame(width: 100, height: 100)
                                            .foregroundColor(.red)
                                            .opacity(showThumbsDown ? 0.8 : 0)
                                            .scaleEffect(showThumbsDown ? 1 : 0.5)
                                            .animation(.spring(response: 0.3), value: showThumbsDown)
                                        
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
                                    }
                                )
                        }
                        .frame(width: geometry.size.width - cardSpacing * 2, height: geometry.size.height - cardSpacing * 2)
                        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                        .rotationEffect(.degrees(rotationAngle))
                        .gesture(
                            DragGesture()
                                .updating($dragOffset) { value, state, _ in
                                    state = value.translation
                                    if !hasStartedPreloading && abs(value.translation.width) > preloadThreshold {
                                        hasStartedPreloading = true
                                        videoManager.preloadNextVideo()
                                    }
                                }
                                .onEnded(onDragEnded)
                        )
                        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: dragOffset)
                        .zIndex(2)
                    } else {
                        // Background placeholder card
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemGray6))
                            
                            VStack(spacing: 15) {
                                Image(systemName: "play.rectangle.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 60)
                                    .foregroundColor(.gray)
                                
                                Text("Next Video")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                            }
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                videoManager.currentPlayer.play()
            }
            .onDisappear {
                videoManager.currentPlayer.pause()
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
        hasStartedPreloading = false
        
        // Check for vertical swipes first
        if abs(dragHeight) > dragThreshold && abs(dragHeight) > abs(dragWidth) {
            if dragHeight < 0 {
                // Swipe up
                withAnimation(.easeOut(duration: 0.2)) {
                    offset.height = -500
                }
                
                showPaperAirplane = true
                
                // Initial fast upward motion
                withAnimation(.easeOut(duration: 0.5)) {
                    paperAirplaneOffset = -200
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    videoManager.handleUpSwipe()
                    withAnimation(.none) {
                        offset = .zero
                        // Continue flying upward while fading out
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeOut(duration: 0.8)) {
                                showPaperAirplane = false
                                paperAirplaneOffset -= 150 // Additional upward motion while fading
                            }
                            // Reset position after completely hidden
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                paperAirplaneOffset = 0
                            }
                        }
                    }
                }
            } else {
                // Swipe down
                withAnimation(.easeOut(duration: 0.2)) {
                    offset.height = 500
                }
                
                showSaveIcon = true
                
                // Initial fast downward motion
                withAnimation(.easeOut(duration: 0.5)) {
                    saveIconOffset = 200
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    videoManager.handleDownSwipe()
                    withAnimation(.none) {
                        offset = .zero
                        // Continue moving downward while fading out
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeOut(duration: 0.8)) {
                                showSaveIcon = false
                                saveIconOffset += 150 // Additional downward motion while fading
                            }
                            // Reset position after completely hidden
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                saveIconOffset = 0
                            }
                        }
                    }
                }
            }
        }
        // Horizontal swipes
        else if abs(dragWidth) > dragThreshold && abs(dragWidth) > abs(dragHeight) {
            let direction: CGFloat = dragWidth > 0 ? 1 : -1
            withAnimation(.easeOut(duration: 0.2)) {
                offset.width = direction * 500
                offset.height = gesture.translation.height
            }
            
            // Show appropriate thumb indicator
            if dragWidth > 0 {
                showThumbsUp = true
            } else {
                showThumbsDown = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if dragWidth > 0 {
                    videoManager.handleRightSwipe()
                } else {
                    videoManager.handleLeftSwipe()
                }
                withAnimation(.none) {
                    offset = .zero
                    // Hide the indicators after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showThumbsUp = false
                        showThumbsDown = false
                    }
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
    SwipeableVideoPlayer()
        .environmentObject(VideoManager())
}
