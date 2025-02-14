import SwiftUI
import UIKit
import UniformTypeIdentifiers
import FirebaseFirestore

// Protocol for items that can be displayed in the grid
protocol GridDisplayable: Identifiable, Equatable {
    var id: String { get }
}

// Generic grid view that can work with any type conforming to GridDisplayable
struct ContentGridView<Item: GridDisplayable, CardView: View>: View {
    let items: [Item]
    let isLoading: Bool
    let isLoadingMore: Bool
    let hasMoreContent: Bool
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    let onLoadMore: () -> Void
    let cardBuilder: (Item) -> CardView
    
    // Grid layout configuration
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    // Shimmer animation state
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        if items.isEmpty && !isLoading {
            Text("No items yet")
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 200)
        } else {
            ZStack(alignment: .top) {
                loadingPlaceholderGrid
                    .opacity(isLoading ? 1 : 0)
                
                itemsGrid
                    .opacity(isLoading ? 0 : 1)
            }
            .animation(.easeInOut(duration: 0.6), value: isLoading)
        }
    }
    
    private var loadingPlaceholderGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<6, id: \.self) { index in
                placeholderCell
                    .transition(.opacity.combined(with: .offset(y: 20)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            startShimmerAnimation()
        }
    }
    
    private var itemsGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                cardBuilder(item)
                    .transition(.opacity.combined(with: .offset(y: 20)))
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                        .delay(Double(index % 20) * 0.1),
                        value: items
                    )
                    .onAppear {
                        if index == items.count - 5 && hasMoreContent {
                            onLoadMore()
                        }
                    }
            }
            
            if isLoadingMore {
                ForEach(0..<2) { _ in
                    placeholderCell
                        .transition(.opacity)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .top)
    }
    
    private var placeholderCell: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.2))
            .frame(width: (UIScreen.main.bounds.width - 36) / 2, height: 280)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.2),
                                Color.white.opacity(0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: shimmerOffset)
                    .mask(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                    )
            )
    }
    
    private func startShimmerAnimation() {
        withAnimation(
            .linear(duration: 1.5)
            .repeatForever(autoreverses: false)
        ) {
            shimmerOffset = UIScreen.main.bounds.width
        }
    }
}

// Video-specific card view
struct SavedVideoCard: View {
    let video: VideoItem
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    @ObservedObject var videoManager: VideoManager
    
    // Local state
    @State private var copiedVideoId: String? = nil
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    @State private var creatorIcons: [String: Data] = [:]
    @State private var showingUsernameForVideo: String? = nil
    
    private let db = Firestore.firestore()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Thumbnail with optimized loading and retry mechanism
            AsyncImage(url: URL(string: "https://image.mux.com/\(video.playback_id)/thumbnail.jpg?time=0&width=200&fit_mode=preserve&quality=75"),
                      transaction: Transaction(animation: .easeInOut(duration: 0.3))) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            ProgressView()
                                .tint(.white.opacity(0.7))
                        )
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                case .failure(_):
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.system(size: 24))
                        )
                @unknown default:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: (UIScreen.main.bounds.width - 36) / 2, height: 280)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Gradient overlay
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.5), location: 0.5),
                    .init(color: .black.opacity(0.9), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Content overlay
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                
                if showingUsernameForVideo == video.id {
                    expandedContent
                } else {
                    previewContent
                }
                
                // Download button
                if let progress = downloadProgress[video.id], progress < 1.0 {
                    downloadProgressView(progress: progress)
                } else {
                    downloadButton
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: (UIScreen.main.bounds.width - 36) / 2, height: 280)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showingUsernameForVideo = showingUsernameForVideo == video.id ? nil : video.id
            }
        }
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
    
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(showsIndicators: false) {
                Text(video.description)
                    .font(.system(size: 14, weight: .regular))
                    .lineSpacing(4)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 8)
                    .padding(.top, 8)
            }
            .frame(maxHeight: 160)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.6), location: 0.2),
                            .init(color: .black, location: 0.4)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 12)
                    
                    Rectangle()
                    
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.2),
                            .init(color: .black.opacity(0.6), location: 0.4),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)
                }
            )
            
            creatorInfo
        }
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 20)),
                removal: .opacity.combined(with: .offset(y: 20))
            )
        )
        .padding(.bottom, 12)
    }
    
    private var previewContent: some View {
        Text(video.description)
            .font(.system(size: 13, weight: .regular))
            .lineLimit(2)
            .foregroundColor(.white.opacity(0.8))
            .padding(.bottom, 12)
    }
    
    private var creatorInfo: some View {
        HStack(spacing: 8) {
            if let iconData = creatorIcons[video.creator] {
                AnimatedGIFView(gifData: iconData)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
            } else {
                Circle()
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .onAppear {
                        Task {
                            await loadCreatorIcon(for: video.creator)
                        }
                    }
            }
            
            Text("@\(video.display_name)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func downloadProgressView(progress: Double) -> some View {
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
    
    private var downloadButton: some View {
        Button(action: {
            startDownload()
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
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copiedVideoId == video.id {
                        copiedVideoId = nil
                    }
                }
            }
        )
    }
    
    private func loadCreatorIcon(for creatorId: String) async {
        guard creatorIcons[creatorId] == nil else { return }
        
        do {
            let docSnapshot = try await db.collection("user_icons").document(creatorId).getDocument()
            
            if let iconData = docSnapshot.data()?["icon_data"] as? String,
               let data = Data(base64Encoded: iconData) {
                await MainActor.run {
                    creatorIcons[creatorId] = data
                }
            }
        } catch {
            print("Failed to load creator icon: \(error.localizedDescription)")
        }
    }
    
    private func startDownload() {
        guard downloadTasks[video.id] == nil else { return }
        
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
                
                let filename = "\(video.display_name)_\(UUID().uuidString).mp4"
                
                guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    print("Could not access documents directory")
                    return
                }
                
                let destinationURL = documentsPath.appendingPathComponent(filename)
                
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    
                    try FileManager.default.moveItem(at: localURL, to: destinationURL)
                    print("✅ Successfully downloaded video to: \(destinationURL.path)")
                    
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
        
        downloadProgress[video.id] = 0.0
        downloadTasks[video.id] = downloadTask
        
        let observation = downloadTask.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                downloadProgress[video.id] = progress.fractionCompleted
            }
        }
        
        objc_setAssociatedObject(downloadTask, "observation", observation, .OBJC_ASSOCIATION_RETAIN)
        
        downloadTask.resume()
    }
}

// Make VideoItem conform to GridDisplayable
extension VideoItem: GridDisplayable {}

// Convenience typealias for the saved videos grid
typealias SavedVideoGridView = ContentGridView<VideoItem, SavedVideoCard> 