import SwiftUI
import AVKit
import UIKit

// Extension to support conditional modifiers
extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}

/// Protocol defining video playback functionality
protocol VideoPlaybackView: View {
    var player: AVQueuePlayer { get }
    var isSwipingAway: Bool { get }
}

/// Protocol for video info display
protocol VideoInfoView: View {
    var video: VideoItem? { get }
}

/// Base VideoCard without any gesture handling
struct VideoCard: View, VideoPlaybackView, VideoInfoView {
    let player: AVQueuePlayer
    let geometry: GeometryProxy
    let cardSpacing: CGFloat
    let isTopCard: Bool
    let isSwipingAway: Bool
    let video: VideoItem?
    
    var body: some View {
        ZStack {
            // Video Player
            AutoplayVideoPlayer(player: player)
                .aspectRatio(9/16, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.top, 60)
                .opacity(isSwipingAway ? 0 : 1)
            
            // Overlay for top card only
            if isTopCard, let video = video {
                VStack {
                    Spacer()
                    VideoInfoOverlay(video: video)
                        .padding(.bottom, 80)
                        .opacity(isSwipingAway ? 0 : 1)
                }
            }
        }
        .frame(
            width: geometry.size.width - cardSpacing * 2,
            height: geometry.size.height - cardSpacing * 2
        )
        .zIndex(isTopCard ? 2 : 1)
    }
}

/// Tap gesture modifier
struct TapGestureModifier: ViewModifier {
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    
    func body(content: Content) -> some View {
        content.gesture(
            SimultaneousGesture(
                TapGesture()
                    .onEnded { _ in onTap() },
                TapGesture(count: 2)
                    .onEnded { _ in onDoubleTap() }
            )
        )
    }
}

/// Swipe gesture modifier
struct SwipeGestureModifier: ViewModifier {
    let configuration: SwipeConfiguration
    
    func body(content: Content) -> some View {
        SwipeableCard(configuration: configuration) {
            content
        }
    }
}

/// Extension to add tap gestures
extension View {
    func withTapGestures(onTap: @escaping () -> Void, onDoubleTap: @escaping () -> Void) -> some View {
        modifier(TapGestureModifier(onTap: onTap, onDoubleTap: onDoubleTap))
    }
    
    func withSwipeGestures(configuration: SwipeConfiguration) -> some View {
        modifier(SwipeGestureModifier(configuration: configuration))
    }
}

struct SwipeableVideoPlayer: View {
    // MARK: - Observed & State Properties
    @ObservedObject var videoManager: VideoManager
    
    // Play/Pause/Restart indicator states
    @State private var showPlayIndicator = false
    @State private var showPauseIndicator = false
    @State private var showRestartIndicator = false
    
    // Refresh state for "caught up" view
    @State private var isRefreshing = false
    
    // Track if a card is being swiped away
    @State private var isSwipingAway = false

    // MARK: - Constants
    private let cardSpacing: CGFloat = 15
    
    private var swipeConfiguration: SwipeConfiguration {
        SwipeConfiguration(
            leftAction: SwipeAction(
                icon: "hand.thumbsdown.fill",
                color: .red,
                rotationDegrees: 0,
                action: { handleSwipeAway(direction: .left) }
            ),
            rightAction: SwipeAction(
                icon: "hand.thumbsup.fill",
                color: .green,
                rotationDegrees: 0,
                action: { handleSwipeAway(direction: .right) }
            ),
            upAction: SwipeAction(
                icon: "paperplane.fill",
                color: .blue,
                rotationDegrees: -45,
                action: { handleSwipeAway(direction: .up) }
            ),
            downAction: SwipeAction(
                icon: "square.and.arrow.down.fill",
                color: .purple,
                rotationDegrees: 0,
                action: { handleSwipeAway(direction: .down) }
            )
        )
    }
    
    // MARK: - Swipe Direction Enum
    private enum SwipeDirection {
        case left, right, up, down
    }
    
    // MARK: - Swipe Handler
    private func handleSwipeAway(direction: SwipeDirection) {
        isSwipingAway = true
        
        // Delay the actual action to match the swipe animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch direction {
            case .left:
                videoManager.handleLeftSwipe()
            case .right:
                videoManager.handleRightSwipe()
            case .up:
                videoManager.handleUpSwipe()
            case .down:
                videoManager.handleDownSwipe()
            }
            isSwipingAway = false
        }
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if videoManager.videoStack.isEmpty {
                    caughtUpView(geometry: geometry)
                } else {
                    ZStack {
                        playPauseRestartIndicators
                        bottomCard(geometry: geometry)
                        SwipeableCard(configuration: swipeConfiguration) {
                            topCardContent(geometry: geometry)
                        }.zIndex(2)
                        
                        // Floating mute button
                        VStack {
                            HStack {
                                Button(action: {
                                    videoManager.toggleMute()
                                }) {
                                    Image(systemName: videoManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .foregroundColor(.white)
                                        .padding(8)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .padding(16)
                                Spacer()
                            }
                            .padding(.top, 70)
                            Spacer()
                        }
                        .zIndex(5) // Ensure it's above all other content
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if !videoManager.videoStack.isEmpty { videoManager.currentPlayer.play() } }
            .onDisappear { videoManager.currentPlayer.pause() }
            .sheet(isPresented: $videoManager.isShowingShareSheet, onDismiss: {
                videoManager.currentPlayer.play()
            }) {
                if let items = videoManager.itemsToShare {
                    ShareSheet(items: items)
                        .onAppear { videoManager.currentPlayer.pause() }
                }
            }
        }
    }
    
    // MARK: - Computed Properties & Helper Views
    
    /// Returns the overlay with play, pause, and restart indicators.
    private var playPauseRestartIndicators: some View {
        ZStack {
            Image(systemName: "play.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.white.opacity(0.8))
                .opacity(showPlayIndicator ? 1 : 0)
                .scaleEffect(showPlayIndicator ? 1 : 0.5)
                .animation(.spring(response: 0.3), value: showPlayIndicator)
            
            Image(systemName: "pause.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.white.opacity(0.8))
                .opacity(showPauseIndicator ? 1 : 0)
                .scaleEffect(showPauseIndicator ? 1 : 0.5)
                .animation(.spring(response: 0.3), value: showPauseIndicator)
            
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.white.opacity(0.8))
                .opacity(showRestartIndicator ? 1 : 0)
                .scaleEffect(showRestartIndicator ? 1 : 0.5)
                .animation(.spring(response: 0.3), value: showRestartIndicator)
        }
        .zIndex(4)
    }
    
    /// The "caught up" view shown when there are no videos.
    private func caughtUpView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(
                    isRefreshing
                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                    : .default,
                    value: isRefreshing
                )
            
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
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
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
    }
    
    /// Returns the bottom card showing the next video.
    @ViewBuilder
    private func bottomCard(geometry: GeometryProxy) -> some View {
        if videoManager.videoStack.count > 1 {
            VideoCard(
                player: videoManager.nextPlayer,
                geometry: geometry,
                cardSpacing: cardSpacing,
                isTopCard: false,
                isSwipingAway: false,
                video: nil
            )
        }
    }

    /// Returns the content for the top card.
    private func topCardContent(geometry: GeometryProxy) -> some View {
        VideoCard(
            player: videoManager.currentPlayer,
            geometry: geometry,
            cardSpacing: cardSpacing,
            isTopCard: true,
            isSwipingAway: isSwipingAway,
            video: videoManager.currentVideo
        )
        .withTapGestures(
            onTap: handleVideoTap,
            onDoubleTap: handleVideoDoubleTap
        )
        .withSwipeGestures(configuration: swipeConfiguration)
    }

    private func handleVideoTap() {
        let isPlaying = videoManager.currentPlayer.timeControlStatus == .playing
        
        withAnimation(.none) {
            showPlayIndicator = false
            showPauseIndicator = false
            showRestartIndicator = false
        }
        
        if isPlaying {
            withAnimation { showPauseIndicator = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation { showPauseIndicator = false }
            }
        } else {
            withAnimation { showPlayIndicator = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation { showPlayIndicator = false }
            }
        }
        
        if isPlaying {
            videoManager.currentPlayer.pause()
        } else {
            videoManager.currentPlayer.play()
        }
    }

    private func handleVideoDoubleTap() {
        withAnimation(.none) {
            showPlayIndicator = false
            showPauseIndicator = false
            showRestartIndicator = false
        }
        
        withAnimation { showRestartIndicator = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation { showRestartIndicator = false }
        }
        
        videoManager.currentPlayer.seek(to: .zero)
        videoManager.currentPlayer.play()
    }
}