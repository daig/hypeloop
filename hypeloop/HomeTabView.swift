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

 