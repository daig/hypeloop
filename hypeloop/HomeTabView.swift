import SwiftUI
import AVKit

struct HomeTabView: View {
    @ObservedObject var videoManager: VideoManager
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background Layer
            Color.black.ignoresSafeArea()
            
            // Video Player Layer
            SwipeableVideoPlayer(videoManager: videoManager)
                .ignoresSafeArea()
            
            // Video Info Overlay at bottom
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    if let currentVideo = videoManager.videoStack.first {
                        Text("@\(currentVideo.creator)")
                            .font(.headline)
                            .bold()
                        Text(currentVideo.description)
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.6)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.bottom, 49) // Adjusted to align with navigation bar
            }
        }
    }
}

struct ReactionButton: View {
    let iconName: String
    let label: String
    let count: String?
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 28))
            if let count = count {
                Text(count)
                    .font(.caption)
                    .bold()
            }
        }
        .foregroundColor(.white)
    }
}

#Preview {
    HomeTabView(videoManager: VideoManager())
} 