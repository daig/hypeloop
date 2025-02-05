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
                                
                                if let progress = downloadProgress[video.id], progress < 1.0 {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ProgressView(value: progress)
                                            .progressViewStyle(.linear)
                                            .tint(.blue)
                                        
                                        HStack {
                                            Text("\(Int(progress * 100))%")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                downloadTasks[video.id]?.cancel()
                                                downloadTasks[video.id] = nil
                                                downloadProgress[video.id] = nil
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.gray)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.top, 4)
                                } else {
                                    Button(action: {
                                        startDownload(video)
                                    }) {
                                        HStack {
                                            Image(systemName: copiedVideoId == video.id ? "checkmark" : "arrow.down.circle")
                                            Text(copiedVideoId == video.id ? "Copied!" : "Download Video")
                                        }
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                    }
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                            UIPasteboard.general.string = video.url.absoluteString
                                            copiedVideoId = video.id
                                            
                                            // Reset the copied status after 2 seconds
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                if copiedVideoId == video.id {
                                                    copiedVideoId = nil
                                                }
                                            }
                                        }
                                    )
                                    .padding(.top, 4)
                                }
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
            .sheet(isPresented: $presentingSafari) {
                if let url = selectedVideoURL {
                    SafariView(url: url)
                }
            }
        }
    }
    
    private func startDownload(_ video: VideoItem) {
        guard downloadTasks[video.id] == nil else { return }
        
        let session = URLSession(configuration: .default)
        let downloadTask = session.downloadTask(with: video.url) { localURL, response, error in
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
                    return
                }
                
                // Get the file extension from the URL or response
                let ext = video.url.pathExtension.isEmpty ? "mp4" : video.url.pathExtension
                
                // Create a unique filename
                let filename = "\(video.creator)_\(UUID().uuidString).\(ext)"
                
                // Get the documents directory
                guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
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

#Preview {
    SavedVideosTabView(videoManager: VideoManager())
} 