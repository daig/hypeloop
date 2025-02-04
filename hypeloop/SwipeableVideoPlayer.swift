import SwiftUI
import AVKit

struct SwipeableVideoPlayer: View {
    @StateObject private var videoManager = VideoManager()
    @GestureState private var dragOffset: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isTransitioning = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = videoManager.currentPlayer {
                    VideoPlayer(player: player)
                        .opacity(isTransitioning ? 0 : 1)
                        .offset(x: offset + dragOffset)
                        .gesture(
                            DragGesture()
                                .updating($dragOffset) { value, state, _ in
                                    state = value.translation.width
                                }
                                .onEnded { value in
                                    let screenWidth = geometry.size.width
                                    let dragThreshold: CGFloat = screenWidth / 3
                                    
                                    withAnimation(.spring()) {
                                        if value.translation.width > dragThreshold {
                                            // Swipe right - go to previous video
                                            if videoManager.currentVideoIndex > 0 {
                                                isTransitioning = true
                                                offset = screenWidth
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                    videoManager.goToPreviousVideo()
                                                    withAnimation(.none) {
                                                        offset = -screenWidth
                                                    }
                                                    withAnimation(.spring()) {
                                                        offset = 0
                                                        isTransitioning = false
                                                    }
                                                }
                                            } else {
                                                offset = 0
                                            }
                                        } else if value.translation.width < -dragThreshold {
                                            // Swipe left - go to next video
                                            isTransitioning = true
                                            offset = -screenWidth
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                videoManager.goToNextVideo()
                                                withAnimation(.none) {
                                                    offset = screenWidth
                                                }
                                                withAnimation(.spring()) {
                                                    offset = 0
                                                    isTransitioning = false
                                                }
                                            }
                                        } else {
                                            // Reset position if drag wasn't far enough
                                            offset = 0
                                        }
                                    }
                                }
                        )
                }
            }
            .onAppear {
                videoManager.currentPlayer?.play()
            }
            .onDisappear {
                videoManager.currentPlayer?.pause()
            }
        }
    }
} 