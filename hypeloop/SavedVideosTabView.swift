import SwiftUI

struct SavedVideosTabView: View {
    @ObservedObject var videoManager: VideoManager
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if videoManager.savedVideos.isEmpty {
                    Text("No saved videos yet")
                        .foregroundColor(.gray)
                } else {
                    List {
                        ForEach(videoManager.savedVideos, id: \.id) { video in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("@\(video.creator)")
                                    .font(.headline)
                                    .bold()
                                Text(video.description)
                                    .font(.subheadline)
                                    .lineLimit(2)
                            }
                            .listRowBackground(Color.black)
                            .foregroundColor(.white)
                        }
                        .onDelete(perform: videoManager.removeSavedVideo)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
        }
    }
}

#Preview {
    SavedVideosTabView(videoManager: VideoManager())
} 