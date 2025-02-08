import SwiftUI
import UIKit
import SafariServices
import UniformTypeIdentifiers
import FirebaseFirestore
import FirebaseAuth

struct SavedVideosTabView: View {
    @ObservedObject var videoManager: VideoManager
    @StateObject private var authService = AuthService.shared
    @State private var copiedVideoId: String? = nil
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    @State private var presentingSafari = false
    @State private var selectedVideoURL: URL? = nil
    @State private var creatorIcons: [String: Data] = [:]
    @State private var showingUsernameForVideo: String? = nil
    @State private var isLoading = true
    @State private var shimmerOffset: CGFloat = -200
    @State private var currentPage = 0
    @State private var hasMoreContent = true
    @State private var isLoadingMore = false
    @State private var thumbnailRetryAttempts: [String: Int] = [:]
    private let videosPerPage = 20
    
    private let db = Firestore.firestore()
    
    // Grid layout configuration
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // User Profile Section - Now fixed at the top
                    VStack(spacing: 16) {
                        // User Icon
                        if let iconData = authService.userIconData {
                            AnimatedGIFView(gifData: iconData)
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    .white.opacity(0.3),
                                                    .white.opacity(0.1)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                )
                        } else {
                            Circle()
                                .fill(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                                .frame(width: 100, height: 100)
                        }
                        
                        // Display Name
                        Text("@\(authService.displayName)")
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 24)
                    
                    // Content Section - Always fills remaining space
                    ScrollView {
                        VStack(spacing: 0) {
                            if videoManager.savedVideos.isEmpty && !isLoading {
                                Text("No saved videos yet")
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .frame(minHeight: 200)
                            } else {
                                ZStack(alignment: .top) {
                                    loadingPlaceholderGrid
                                        .opacity(isLoading ? 1 : 0)
                                    
                                    savedVideosGrid
                                        .opacity(isLoading ? 0 : 1)
                                }
                                .animation(.easeInOut(duration: 0.6), value: isLoading)
                            }
                            
                            // Add spacer at the bottom to push content to top
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .sheet(isPresented: $presentingSafari) {
                if let url = selectedVideoURL {
                    SafariView(url: url)
                }
            }
            .task {
                await loadSavedVideos()
            }
            .refreshable {
                await loadSavedVideos()
            }
        }
    }
    
    private func loadSavedVideos() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        currentPage = 0
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("saved_videos")
                .order(by: "saved_at", descending: true)
                .limit(to: videosPerPage)
                .getDocuments()
            
            let videos = snapshot.documents.compactMap { document -> VideoItem? in
                let data = document.data()
                return VideoItem(
                    id: data["id"] as? String ?? "",
                    playback_id: data["playback_id"] as? String ?? "",
                    creator: data["creator"] as? String ?? "",
                    display_name: data["display_name"] as? String ?? "",
                    description: data["description"] as? String ?? "",
                    created_at: Double(data["created_at"] as? Int ?? 0),
                    status: "ready"
                )
            }
            
            hasMoreContent = !snapshot.documents.isEmpty && snapshot.documents.count == videosPerPage
            
            await MainActor.run {
                videoManager.savedVideos = videos
                isLoading = false
            }
        } catch {
            print("Error loading saved videos: \(error.localizedDescription)")
            isLoading = false
        }
    }
    
    private func loadMoreContent() async {
        guard let userId = Auth.auth().currentUser?.uid,
              hasMoreContent && !isLoadingMore,
              !videoManager.savedVideos.isEmpty else { return }
        
        isLoadingMore = true
        
        do {
            let lastVideo = videoManager.savedVideos.last
            let snapshot = try await db.collection("users").document(userId)
                .collection("saved_videos")
                .order(by: "saved_at", descending: true)
                .start(after: [lastVideo?.created_at ?? 0])
                .limit(to: videosPerPage)
                .getDocuments()
            
            let newVideos = snapshot.documents.compactMap { document -> VideoItem? in
                let data = document.data()
                return VideoItem(
                    id: data["id"] as? String ?? "",
                    playback_id: data["playback_id"] as? String ?? "",
                    creator: data["creator"] as? String ?? "",
                    display_name: data["display_name"] as? String ?? "",
                    description: data["description"] as? String ?? "",
                    created_at: Double(data["created_at"] as? Int ?? 0),
                    status: "ready"
                )
            }
            
            hasMoreContent = !snapshot.documents.isEmpty && snapshot.documents.count == videosPerPage
            
            await MainActor.run {
                videoManager.savedVideos.append(contentsOf: newVideos)
                currentPage += 1
                isLoadingMore = false
            }
        } catch {
            print("Error loading more videos: \(error.localizedDescription)")
            isLoadingMore = false
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
    
    private func startShimmerAnimation() {
        withAnimation(
            .linear(duration: 1.5)
            .repeatForever(autoreverses: false)
        ) {
            shimmerOffset = UIScreen.main.bounds.width
        }
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
    
    private var savedVideosGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(videoManager.savedVideos.enumerated()), id: \.element.id) { index, video in
                savedVideoCell(for: video)
                    .transition(.opacity.combined(with: .offset(y: 20)))
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                        .delay(Double(index % videosPerPage) * 0.1),
                        value: videoManager.savedVideos
                    )
                    .onAppear {
                        if index == videoManager.savedVideos.count - 5 && hasMoreContent {
                            Task {
                                await loadMoreContent()
                            }
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
    
    private func savedVideoCell(for video: VideoItem) -> some View {
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
                        .onAppear {
                            let currentAttempt = thumbnailRetryAttempts[video.id] ?? 0
                            let maxAttempts = 5 // Maximum number of retry attempts
                            
                            if currentAttempt < maxAttempts {
                                // Calculate delay with exponential backoff (2^n seconds)
                                let delay = pow(2.0, Double(currentAttempt))
                                thumbnailRetryAttempts[video.id] = currentAttempt + 1
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    // Clear the image cache for this URL
                                    URLCache.shared.removeCachedResponse(
                                        for: URLRequest(
                                            url: URL(string: "https://image.mux.com/\(video.playback_id)/thumbnail.jpg?time=0&width=200&fit_mode=preserve&quality=75")!
                                        )
                                    )
                                    // Force a view update to trigger a new image load
                                    withAnimation {
                                        // Using a temporary state update to force a view refresh
                                        let tempAttempts = thumbnailRetryAttempts
                                        thumbnailRetryAttempts = [:]
                                        DispatchQueue.main.async {
                                            thumbnailRetryAttempts = tempAttempts
                                        }
                                    }
                                }
                            }
                        }
                @unknown default:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: (UIScreen.main.bounds.width - 36) / 2, height: 280)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .id("\(video.id)_\(thumbnailRetryAttempts[video.id] ?? 0)") // Update id to force refresh on retry
            
            // Gradient overlay - stronger at bottom for better text contrast
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
                    // Expanded content when tapped
                    VStack(alignment: .leading, spacing: 12) {
                        // Description with scroll for long text
                        ScrollView(showsIndicators: false) {
                            Text(video.description)
                                .font(.system(size: 14, weight: .regular))
                                .lineSpacing(4)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.leading)
                                .padding(.bottom, 8)
                                .padding(.top, 8) // Add padding for top fade
                        }
                        .frame(maxHeight: 160)
                        .mask(
                            VStack(spacing: 0) {
                                // Top fade - smoother transition
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
                                
                                // Middle solid section
                                Rectangle()
                                
                                // Bottom fade - even softer transition
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
                        
                        // Creator info
                        HStack(spacing: 8) {
                            // Creator icon
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
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 20)),
                            removal: .opacity.combined(with: .offset(y: 20))
                        )
                    )
                    .padding(.bottom, 12)
                } else {
                    // Preview text when not tapped
                    Text(video.description)
                        .font(.system(size: 13, weight: .regular))
                        .lineLimit(2)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 12)
                }
                
                // Download button - always visible
                if let progress = downloadProgress[video.id], progress < 1.0 {
                    downloadProgressView(for: video, progress: progress)
                } else {
                    downloadButton(for: video)
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

 