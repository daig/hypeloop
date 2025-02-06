import SwiftUI
import UIKit
import SafariServices
import UniformTypeIdentifiers

struct SavedVideosTabView: View {
    @ObservedObject var videoManager: VideoManager
    @State private var copiedVideoId: String? = nil
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    @State private var presentingSafari = false
    @State private var selectedVideoURL: URL? = nil
    
    // Grid layout configuration
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                Group {
                    if videoManager.savedVideos.isEmpty {
                        Text("No saved videos yet")
                            .foregroundColor(.gray)
                    } else {
                        savedVideosGrid
                    }
                }
            }
            .navigationTitle("Saved Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .sheet(isPresented: $presentingSafari) {
                if let url = selectedVideoURL {
                    SafariView(url: url)
                }
            }
        }
    }
    
    private var savedVideosGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(videoManager.savedVideos, id: \.id) { video in
                    savedVideoCell(for: video)
                }
            }
            .padding(12)
        }
    }
    
    private func savedVideoCell(for video: VideoItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail
            AsyncImage(url: URL(string: "https://image.mux.com/\(video.playback_id)/thumbnail.jpg?time=0&width=200&fit_mode=preserve&quality=75")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: (UIScreen.main.bounds.width - 36) / 2, height: 280)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Gradient overlay
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Text overlay
            VStack(alignment: .leading, spacing: 4) {
                Text("@\(video.display_name)")
                    .font(.headline)
                    .bold()
                    .lineLimit(1)
                
                Text(video.description)
                    .font(.subheadline)
                    .lineLimit(2)
                
                // Download button
                if let progress = downloadProgress[video.id], progress < 1.0 {
                    downloadProgressView(for: video, progress: progress)
                } else {
                    downloadButton(for: video)
                }
            }
            .padding(12)
        }
        .frame(width: (UIScreen.main.bounds.width - 36) / 2, height: 280)
        .contextMenu {
            Button(role: .destructive) {
                if let index = videoManager.savedVideos.firstIndex(where: { $0.id == video.id }) {
                    videoManager.removeSavedVideo(at: IndexSet(integer: index))
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func downloadProgressView(for video: VideoItem, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)
            
            HStack {
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                
                Spacer()
                
                Button(action: {
                    downloadTasks[video.id]?.cancel()
                    downloadTasks[video.id] = nil
                    downloadProgress[video.id] = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func downloadButton(for video: VideoItem) -> some View {
        Button(action: {
            startDownload(video)
        }) {
            HStack {
                Image(systemName: copiedVideoId == video.id ? "checkmark" : "arrow.down.circle")
                Text(copiedVideoId == video.id ? "Copied!" : "Download Video")
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .font(.caption)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                UIPasteboard.general.string = video.playbackUrl.absoluteString
                copiedVideoId = video.id
                
                // Reset the copied status after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copiedVideoId == video.id {
                        copiedVideoId = nil
                    }
                }
            }
        )
    }
    
    private func startDownload(_ video: VideoItem) {
        guard downloadTasks[video.id] == nil else { return }
        
        // Construct the MP4 download URL
        // Using Mux's capped-1080p.mp4 format which is optimized for download
        let downloadURL = URL(string: "https://stream.mux.com/\(video.playback_id)/capped-1080p.mp4")!
        
        let session = URLSession(configuration: .default)
        let downloadTask = session.downloadTask(with: downloadURL) { localURL, response, error in
            DispatchQueue.main.async {
                downloadTasks[video.id] = nil
                downloadProgress[video.id] = nil
                
                if let error = error {
                    print("Download error: \(error.localizedDescription)")
                    return
                }
                
                guard let localURL = localURL,
                      let response = response as? HTTPURLResponse,
                      response.statusCode == 200 else {
                    print("Invalid response or missing file")
                    return
                }
                
                // Create a unique filename with mp4 extension
                let filename = "\(video.display_name)_\(UUID().uuidString).mp4"
                
                // Get the documents directory
                guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    print("Could not access documents directory")
                    return
                }
                
                let destinationURL = documentsPath.appendingPathComponent(filename)
                
                do {
                    // Remove any existing file
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    
                    // Move downloaded file to documents
                    try FileManager.default.moveItem(at: localURL, to: destinationURL)
                    print("✅ Successfully downloaded video to: \(destinationURL.path)")
                    
                    // Show the share sheet for the downloaded file
                    DispatchQueue.main.async {
                        let activityVC = UIActivityViewController(
                            activityItems: [destinationURL],
                            applicationActivities: nil
                        )
                        
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let rootVC = window.rootViewController {
                            activityVC.popoverPresentationController?.sourceView = rootVC.view
                            rootVC.present(activityVC, animated: true)
                        }
                    }
                } catch {
                    print("File error: \(error.localizedDescription)")
                }
            }
        }
        
        // Set up progress tracking
        downloadProgress[video.id] = 0.0
        downloadTasks[video.id] = downloadTask
        
        let observation = downloadTask.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                downloadProgress[video.id] = progress.fractionCompleted
            }
        }
        
        // Store the observation to prevent it from being deallocated
        objc_setAssociatedObject(downloadTask, "observation", observation, .OBJC_ASSOCIATION_RETAIN)
        
        downloadTask.resume()
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

 