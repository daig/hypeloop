import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Photos
import AVFoundation
import FirebaseFunctions
import PhotosUI
import AVKit
import FirebaseStorage
import ImageIO
import UIKit

struct MuxUploadResponse: Codable {
    let uploadUrl: String
    let uploadId: String
    let filename: String
    let contentType: String
    let fileSize: Int
}

enum StoryOutputDestination {
    case photos
    case upload  
}

class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    var onProgress: (Double) -> Void
    
    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 100
        DispatchQueue.main.async {
            self.onProgress(progress)
        }
    }
}

struct IncubatingStory: Identifiable, Equatable {
    let id: String
    let creator: String
    let created_at: Double
    let numKeyframes: Int
    let status: String
    let scenesRendered: Int
    let sceneCount: Int
    
    static func == (lhs: IncubatingStory, rhs: IncubatingStory) -> Bool {
        lhs.id == rhs.id &&
        lhs.creator == rhs.creator &&
        lhs.created_at == rhs.created_at &&
        lhs.numKeyframes == rhs.numKeyframes &&
        lhs.status == rhs.status &&
        lhs.scenesRendered == rhs.scenesRendered &&
        lhs.sceneCount == rhs.sceneCount
    }
}

// Make IncubatingStory conform to GridDisplayable
extension IncubatingStory: GridDisplayable {}

// Dedicated card view for incubating stories
struct IncubatingStoryCard: View {
    let story: IncubatingStory
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    @Binding var isHatching: Bool
    @Binding var hatchingProgress: String
    @Binding var isUploading: Bool
    @Binding var isOptimizing: Bool
    @Binding var uploadProgress: Double
    let onDelete: (String) -> Void
    let onHatch: (IncubatingStory, Bool) -> Void
    
    var body: some View {
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
                    onHatch(story, true)
                } label: {
                    Label("Hatch & Upload", systemImage: "icloud.and.arrow.up")
                }
                
                Button {
                    onHatch(story, false)
                } label: {
                    Label("Hatch & Save", systemImage: "square.and.arrow.down")
                }
            }
            
            Button(role: .destructive) {
                onDelete(story.id)
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
}

struct IncubatingStoriesTabView: View {
    @StateObject private var authService = AuthService.shared
    @State private var incubatingStories: [IncubatingStory] = []
    @State private var isLoading = true
    
    // Upload progress states
    @State private var isOptimizing = false
    @State private var uploadProgress: Double = 0.0
    @FocusState private var isDescriptionFocused: Bool
    @State private var isUploading = false
    @State private var uploadComplete = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    // Hatching states (separate from main upload)
    @State private var isHatching = false
    @State private var hatchingProgress = ""
    @State private var isHatchingUpload = false
    @State private var isHatchingOptimizing = false
    @State private var hatchingUploadProgress: Double = 0.0

    @State private var selectedVideoURL: URL? = nil
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var description: String = ""
    @State private var isLoadingVideo = false
    
    // Story generation states
    @State private var isGeneratingStory = false
    @State private var storyGenerationResponse: String = ""
    @State private var useMotion = true
    @State private var numKeyframes: Int = 4
    
    // Story merging states
    @State private var showingStoryPicker = false
    @State private var selectedStoryId: String? = nil
    @State private var isLoadingStoryAssets = false
    @State private var storyMergeProgress: String = ""
    @State private var shouldUpload = false
    
    // Add state for sheet
    @State private var showDescriptionSheet = false
    
    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-central1")
    
    // MARK: - Helper Functions
    
    private func handleVideoSelection(_ newItem: PhotosPickerItem?) async {
        selectedVideoURL = nil
        description = ""
        uploadProgress = 0
        isUploading = false
        uploadComplete = false
        isLoadingVideo = true
        
        if let newItem = newItem {
            if let data = try? await newItem.loadTransferable(type: Data.self) {
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "\(UUID().uuidString).mov"
                let fileURL = tempDir.appendingPathComponent(fileName)
                
                do {
                    try data.write(to: fileURL)
                    selectedVideoURL = fileURL
                } catch {
                    print("Error saving video: \(error.localizedDescription)")
                    alertMessage = "Failed to process video"
                    showAlert = true
                }
            }
        }
        isLoadingVideo = false
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
    
    private func getMuxUploadUrl(filename: String, fileSize: Int, contentType: String, description: String) async throws -> MuxUploadResponse {
        let callable = functions.httpsCallable("getVideoUploadUrl")
        
        let data: [String: Any] = [
            "filename": filename,
            "fileSize": fileSize,
            "contentType": contentType,
            "description": description
        ]
        
        let result = try await callable.call(data)
        
        guard let response = try? JSONSerialization.data(withJSONObject: result.data) else {
            throw NSError(domain: "MuxUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return try JSONDecoder().decode(MuxUploadResponse.self, from: response)
    }
    
    private func resetUploadState() {
        selectedItem = nil
        selectedVideoURL = nil
        description = ""
        isUploading = false
        isOptimizing = false
        uploadProgress = 0
        uploadComplete = false
        isLoadingVideo = false
        showDescriptionSheet = false
    }
    
    private func resetHatchingState() {
        isHatching = false
        hatchingProgress = ""
        isHatchingUpload = false
        isHatchingOptimizing = false
        hatchingUploadProgress = 0
    }
    
    private func uploadVideo(from videoURL: URL, description: String, isHatchingMode: Bool = false) async {
        if isHatchingMode {
            isHatchingOptimizing = true
            hatchingUploadProgress = 0
        } else {
            isOptimizing = true
            uploadProgress = 0
        }
        isDescriptionFocused = false
        
        do {
            let optimizedURL = try await optimizeVideo(from: videoURL)
            
            if isHatchingMode {
                isHatchingOptimizing = false
                isHatchingUpload = true
            } else {
                isOptimizing = false
                isUploading = true
            }
            
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: optimizedURL.path)
            let fileSize = fileAttributes[FileAttributeKey.size] as? Int ?? 0
            
            let muxResponse = try await getMuxUploadUrl(
                filename: optimizedURL.lastPathComponent,
                fileSize: fileSize,
                contentType: "video/mp4",
                description: description
            )
            
            let user = Auth.auth().currentUser!
            let uid = user.uid
            
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
            
            // Create a separate progress delegate for hatching uploads
            let progressDelegate = UploadProgressDelegate { progress in
                if isHatchingMode {
                    self.hatchingUploadProgress = progress
                } else {
                    self.uploadProgress = progress
                }
            }
            
            let session = URLSession(configuration: .default, delegate: progressDelegate, delegateQueue: nil)
            var request = URLRequest(url: URL(string: muxResponse.uploadUrl)!)
            request.httpMethod = "PUT"
            request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
            
            let (_, response) = try await session.upload(for: request, from: Data(contentsOf: optimizedURL))
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NSError(domain: "MuxUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
            }
            
            await updateVideoStatus(assetId: muxResponse.uploadId)
            
            // Clean up temporary files
            try? FileManager.default.removeItem(at: optimizedURL)
            try? FileManager.default.removeItem(at: videoURL)
            
            if isHatchingMode {
                resetHatchingState()
            } else {
                resetUploadState()
            }
            
        } catch {
            alertMessage = "Upload failed: \(error.localizedDescription)"
            showAlert = true
            
            if isHatchingMode {
                resetHatchingState()
            } else {
                resetUploadState()
            }
        }
    }
    
    private func updateVideoStatus(assetId: String) async {
        do {
            try await db.collection("videos").document(assetId).updateData([
                "status": "uploading"
            ])
        } catch {
            print("Error updating video status: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Story Generation Functions
    
    private func testStoryGeneration(numKeyframes: Int, isFullBuild: Bool) async throws -> String {
        isGeneratingStory = true
        
        guard let user = Auth.auth().currentUser else {
            alertMessage = "Please sign in to generate stories"
            isGeneratingStory = false
            showAlert = true
            throw NSError(domain: "StoryGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let callable = functions.httpsCallable("generateStoryFunction")
        
        let data: [String: Any] = [
            "keywords": ["magical forest", "lost child", "friendly dragon"],
            "config": [
                "extract_chars": true,
                "generate_voiceover": true,
                "generate_images": true,
                "generate_motion": true,
                "save_script": true,
                "num_keyframes": numKeyframes,
                "output_dir": "output"
            ]
        ]
        
        let result = try await callable.call(data)
        
        if let resultData = result.data as? [String: Any] {
            storyGenerationResponse = "Story generation successful: \(resultData)"
            
            if let storyId = resultData["storyId"] as? String {
                alertMessage = "Story generation completed! Starting asset generation..."
                showAlert = true
                isGeneratingStory = false
                return storyId
            } else {
                throw NSError(domain: "StoryGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Story ID not found in response"])
            }
        } else {
            alertMessage = "Story generation completed but response format was unexpected"
            throw NSError(domain: "StoryGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
        }
    }
    
    private func mergeStoryAssets(useMotion: Bool, outputTo destination: StoryOutputDestination = .photos) async {
        guard let storyId = selectedStoryId else { return }
        isLoadingStoryAssets = true
        storyMergeProgress = "Loading story assets..."
        
        do {
            let stitchedURL = try await mergeStoryAssets(storyId: storyId, useMotion: useMotion)

            switch destination {
            case .photos:
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .video, fileURL: stitchedURL, options: nil)
                }
                alertMessage = "Story assets merged successfully! The video has been saved to your Photos library."
                
            case .upload:
                await uploadVideo(from: stitchedURL, description: "Generated Story", isHatchingMode: true)
                alertMessage = "Story assets merged and uploaded successfully!"
            }
            
            try? FileManager.default.removeItem(at: stitchedURL)
            selectedStoryId = nil
            
        } catch {
            alertMessage = "Failed to merge story assets: \(error.localizedDescription)"
        }
        
        showAlert = true
        isLoadingStoryAssets = false
        storyMergeProgress = ""
    }
    
    private func mergeStoryAssets(storyId: String, useMotion: Bool) async throws -> URL {
        return try await VideoMerger.mergeStoryAssets(
            storyId: storyId,
            useMotion: useMotion,
            progressCallback: { message in
                storyMergeProgress = message
            }
        )
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Creation Controls Section
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                // Upload Video Button
                                PhotosPicker(
                                    selection: $selectedItem,
                                    matching: .videos,
                                    photoLibrary: .shared()
                                ) {
                                    VStack(spacing: 4) {
                                        if isOptimizing || isUploading {
                                            VStack(spacing: 4) {
                                                if isOptimizing {
                                                    Text("Optimizing...")
                                                } else {
                                                    Text("\(Int(uploadProgress))%")
                                                }
                                                ProgressView()
                                                    .progressViewStyle(LinearProgressViewStyle())
                                                    .frame(maxWidth: 100)
                                            }
                                        } else {
                                            Image(systemName: "video.badge.plus")
                                                .font(.system(size: 24))
                                            Text("Upload")
                                                .font(.caption)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(white: 0.15))
                                    .cornerRadius(8)
                                }
                                .onChange(of: selectedItem) { newItem in
                                    Task {
                                        await handleVideoSelection(newItem)
                                        if newItem != nil {
                                            showDescriptionSheet = true
                                        }
                                    }
                                }
                                
                                // Generate Story Button
                                Button {
                                    Task {
                                        do {
                                            selectedStoryId = try await testStoryGeneration(numKeyframes: numKeyframes, isFullBuild: true)
                                        } catch {
                                            alertMessage = error.localizedDescription
                                            showAlert = true
                                        }
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        if isGeneratingStory || isLoadingStoryAssets {
                                            VStack(spacing: 4) {
                                                if isGeneratingStory {
                                                    Text("Generating...")
                                                } else {
                                                    Text(storyMergeProgress)
                                                }
                                                ProgressView()
                                                    .progressViewStyle(LinearProgressViewStyle())
                                                    .frame(maxWidth: 100)
                                            }
                                        } else {
                                            Image(systemName: "wand.and.stars")
                                                .font(.system(size: 24))
                                            Text("Generate")
                                                .font(.caption)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(white: 0.15))
                                    .cornerRadius(8)
                                }
                                .disabled(isGeneratingStory)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        
                        // Existing Grid View
                        ContentGridView(
                            items: incubatingStories,
                            isLoading: isLoading,
                            isLoadingMore: false,
                            hasMoreContent: false,
                            showAlert: $showAlert,
                            alertMessage: $alertMessage,
                            onLoadMore: {},
                            cardBuilder: { story in
                                IncubatingStoryCard(
                                    story: story,
                                    showAlert: $showAlert,
                                    alertMessage: $alertMessage,
                                    isHatching: $isHatching,
                                    hatchingProgress: $hatchingProgress,
                                    isUploading: $isHatchingUpload,
                                    isOptimizing: $isHatchingOptimizing,
                                    uploadProgress: $hatchingUploadProgress,
                                    onDelete: { storyId in
                                        Task {
                                            await deleteStory(storyId)
                                        }
                                    },
                                    onHatch: { story, shouldUpload in
                                        Task {
                                            await hatchStory(story, shouldUpload: shouldUpload)
                                        }
                                    }
                                )
                            }
                        )
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
            .alert("Upload Status", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showDescriptionSheet) {
                // Description Sheet
                NavigationView {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            TextField("Description", text: $description)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isDescriptionFocused)
                                .padding()
                            
                            Button {
                                isDescriptionFocused = false
                                showDescriptionSheet = false
                                Task {
                                    if let videoURL = selectedVideoURL {
                                        await uploadVideo(from: videoURL, description: description)
                                    }
                                }
                            } label: {
                                Text("Start Upload")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(description.isEmpty ? Color.gray : Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .disabled(description.isEmpty)
                            .padding(.horizontal)
                        }
                    }
                    .navigationTitle("Add Description")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showDescriptionSheet = false
                                selectedVideoURL = nil
                                selectedItem = nil
                                description = ""
                            }
                        }
                    }
                }
                .presentationDetents([.height(200)])
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
                // Upload the stitched video with hatching flag
                await uploadVideo(from: stitchedURL, description: "Hatched Story", isHatchingMode: true)
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
            resetHatchingState()
        }
        
        showAlert = true
    }
} 