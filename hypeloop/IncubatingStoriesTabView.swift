import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Photos
import AVFoundation
import FirebaseFunctions

struct IncubatingStory: Identifiable {
    let id: String
    let creator: String
    let created_at: Double
    let numKeyframes: Int
    let status: String
    let scenesRendered: Int
    let sceneCount: Int
}

struct IncubatingStoriesTabView: View {
    @StateObject private var authService = AuthService.shared
    @State private var incubatingStories: [IncubatingStory] = []
    @State private var isLoading = true
    @State private var shimmerOffset: CGFloat = -200
    @State private var isHatching = false
    @State private var hatchingProgress: String = ""
    @State private var isUploading = false
    @State private var isOptimizing = false
    @State private var uploadProgress: Double = 0
    @State private var showAlert = false
    @State private var alertMessage = ""
    
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
                
                ScrollView {
                    if incubatingStories.isEmpty && !isLoading {
                        Text("No incubating stories")
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(minHeight: 200)
                    } else {
                        ZStack(alignment: .top) {
                            loadingPlaceholderGrid
                                .opacity(isLoading ? 1 : 0)
                            
                            incubatingStoriesGrid
                                .opacity(isLoading ? 0 : 1)
                        }
                        .animation(.easeInOut(duration: 0.6), value: isLoading)
                    }
                }
            }
            .navigationTitle("Incubating")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .task {
                await loadIncubatingStories()
            }
            .refreshable {
                await loadIncubatingStories()
            }
        }
    }
    
    private func loadIncubatingStories() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        do {
            // Simpler query that doesn't require a composite index
            let snapshot = try await db.collection("stories")
                .whereField("creator", isEqualTo: userId)
                .whereField("status", isEqualTo: "incubating")
                .getDocuments()
            
            let stories = snapshot.documents.compactMap { document -> IncubatingStory? in
                let data = document.data()
                return IncubatingStory(
                    id: document.documentID,
                    creator: data["creator"] as? String ?? "",
                    created_at: Double(data["created_at"] as? Int ?? 0),
                    numKeyframes: data["num_keyframes"] as? Int ?? 0,
                    status: data["status"] as? String ?? "",
                    scenesRendered: data["scenesRendered"] as? Int ?? 0,
                    sceneCount: data["sceneCount"] as? Int ?? 0
                )
            }
            
            // Sort in memory
            let sortedStories = stories.sorted { $0.created_at > $1.created_at }
            
            await MainActor.run {
                incubatingStories = sortedStories
                isLoading = false
            }
        } catch {
            print("Error loading incubating stories: \(error.localizedDescription)")
            isLoading = false
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
    
    private var incubatingStoriesGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(incubatingStories) { story in
                incubatingStoryCell(for: story)
                    .transition(.opacity.combined(with: .offset(y: 20)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .top)
    }
    
    private func incubatingStoryCell(for story: IncubatingStory) -> some View {
        ZStack(alignment: .bottom) {
            // Egg background with gradient
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.2, blue: 0.3),
                            Color(red: 0.3, green: 0.2, blue: 0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Content overlay
            VStack(spacing: 12) {
                // Egg icon
                Image(systemName: "circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.8))
                    .scaleEffect(y: 1.2)  // Make it slightly taller to look more egg-like
                
                // Progress indicator
                ProgressView(value: Double(story.scenesRendered), total: Double(story.sceneCount))
                    .tint(.white)
                    .frame(width: 100)
                
                // Progress text
                Text("\(story.scenesRendered)/\(story.sceneCount) scenes")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                // Status text
                Text("Incubating...")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                
                // Keyframes info
                Text("\(story.numKeyframes) keyframes")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                
                // Time elapsed
                Text(timeElapsed(since: story.created_at))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                
                // Add hatching progress if active
                if isHatching {
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text(hatchingProgress)
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
                
                if isUploading || isOptimizing {
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text(isUploading ? "Uploading \(Int(uploadProgress))%" :
                             isOptimizing ? "Optimizing video..." : "")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding()
        }
        .frame(width: (UIScreen.main.bounds.width - 36) / 2, height: 280)
        .contextMenu {
            if story.scenesRendered >= story.sceneCount {
                Button {
                    Task {
                        await hatchStory(story, shouldUpload: true)
                    }
                } label: {
                    Label("Hatch & Upload", systemImage: "icloud.and.arrow.up")
                }
                
                Button {
                    Task {
                        await hatchStory(story, shouldUpload: false)
                    }
                } label: {
                    Label("Hatch & Save", systemImage: "square.and.arrow.down")
                }
            }
            
            Button(role: .destructive) {
                Task {
                    await deleteStory(story.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func timeElapsed(since timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp / 1000)
        let elapsed = Date().timeIntervalSince(date)
        
        switch elapsed {
        case ..<60:
            return "Just now"
        case ..<3600:
            let minutes = Int(elapsed / 60)
            return "\(minutes)m ago"
        case ..<86400:
            let hours = Int(elapsed / 3600)
            return "\(hours)h ago"
        default:
            let days = Int(elapsed / 86400)
            return "\(days)d ago"
        }
    }
    
    private func deleteStory(_ storyId: String) async {
        do {
            try await db.collection("stories").document(storyId).delete()
            await loadIncubatingStories()
        } catch {
            print("Error deleting story: \(error.localizedDescription)")
        }
    }
    
    private func hatchStory(_ story: IncubatingStory, shouldUpload: Bool) async {
        isHatching = true
        hatchingProgress = "Loading story assets..."
        
        do {
            let stitchedURL = try await VideoMerger.mergeStoryAssets(
                storyId: story.id,
                useMotion: true,
                progressCallback: { message in
                    hatchingProgress = message
                }
            )
            
            if shouldUpload {
                // Upload the stitched video
                await uploadVideo(from: stitchedURL, description: "Hatched Story")
                alertMessage = "Story hatched and uploaded successfully!"
            } else {
                // Save to Photos library
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .video, fileURL: stitchedURL, options: nil)
                }
                alertMessage = "Story hatched successfully! The video has been saved to your Photos library."
            }
            
            // Clean up
            try? FileManager.default.removeItem(at: stitchedURL)
            
        } catch {
            alertMessage = "Failed to hatch story: \(error.localizedDescription)"
        }
        
        showAlert = true
        isHatching = false
        hatchingProgress = ""
    }

    private func uploadVideo(from videoURL: URL, description: String) async {
        isOptimizing = true
        uploadProgress = 0
        
        do {
            print("🔄 Optimizing video...")
            let optimizedURL = try await optimizeVideo(from: videoURL)
            print("✅ Video optimized successfully")
            
            isOptimizing = false
            isUploading = true
            
            // Get file size and prepare for upload
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: optimizedURL.path)
            let fileSize = fileAttributes[FileAttributeKey.size] as? Int ?? 0
            
            let callable = Functions.functions().httpsCallable("getVideoUploadUrl")
            let data: [String: Any] = [
                "filename": optimizedURL.lastPathComponent,
                "fileSize": fileSize,
                "contentType": "video/mp4",
                "description": description
            ]
            
            let result = try await callable.call(data)
            guard let responseData = try? JSONSerialization.data(withJSONObject: result.data),
                  let muxResponse = try? JSONDecoder().decode(MuxUploadResponse.self, from: responseData) else {
                throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
            }
            
            // Create initial Firestore document
            let user = Auth.auth().currentUser!
            let uid = user.uid
            
            // Get the user identifier for display name generation
            let userIdentifier: String
            if user.providerData.first?.providerID == "apple.com" {
                userIdentifier = user.email ?? user.displayName ?? "Anonymous"
            } else {
                userIdentifier = user.displayName ?? user.email ?? "Anonymous"
            }
            
            let identifierHash = CreatorNameGenerator.generateCreatorHash(userIdentifier)
            let displayName = CreatorNameGenerator.generateDisplayName(from: identifierHash)
            
            try await db.collection("videos").document(muxResponse.uploadId).setData([
                "id": muxResponse.uploadId,
                "creator": uid,
                "display_name": displayName,
                "description": description,
                "created_at": Int(Date().timeIntervalSince1970 * 1000),
                "status": "uploading"
            ])
            
            // Upload to Mux
            let videoData = try Data(contentsOf: optimizedURL)
            var request = URLRequest(url: URL(string: muxResponse.uploadUrl)!)
            request.httpMethod = "PUT"
            request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
            
            let progressDelegate = UploadProgressDelegate { progress in
                self.uploadProgress = progress
            }
            
            let session = URLSession(configuration: .default, delegate: progressDelegate, delegateQueue: nil)
            let (_, response) = try await session.upload(for: request, from: videoData)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
            }
            
            isUploading = false
            uploadProgress = 0
            
            // Clean up temporary files
            try? FileManager.default.removeItem(at: optimizedURL)
            try? FileManager.default.removeItem(at: videoURL)
            
        } catch {
            alertMessage = "Upload failed: \(error.localizedDescription)"
            showAlert = true
            isUploading = false
            isOptimizing = false
            uploadProgress = 0
        }
    }
    
    private func optimizeVideo(from sourceURL: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("\(UUID().uuidString).mp4")
        
        let asset = AVAsset(url: sourceURL)
        
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        let transformedSize = naturalSize.applying(preferredTransform)
        let videoIsPortrait = abs(transformedSize.height) > abs(transformedSize.width)
        
        let exportPreset = videoIsPortrait ? AVAssetExportPreset960x540 : AVAssetExportPreset1280x720
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: exportPreset
        ) else {
            throw NSError(domain: "VideoExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw exportSession.error ?? NSError(domain: "VideoExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
        
        return outputURL
    }
} 