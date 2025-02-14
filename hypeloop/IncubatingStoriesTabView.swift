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
import Network

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
    let keywords: [String]
    var isHatching: Bool = false
    var hatchingProgress: String = ""
    var isHatchingUpload: Bool = false
    var isHatchingOptimizing: Bool = false
    var hatchingUploadProgress: Double = 0
    
    static func == (lhs: IncubatingStory, rhs: IncubatingStory) -> Bool {
        lhs.id == rhs.id &&
        lhs.creator == rhs.creator &&
        lhs.created_at == rhs.created_at &&
        lhs.numKeyframes == rhs.numKeyframes &&
        lhs.status == rhs.status &&
        lhs.scenesRendered == rhs.scenesRendered &&
        lhs.sceneCount == rhs.sceneCount &&
        lhs.keywords == rhs.keywords &&
        lhs.isHatching == rhs.isHatching &&
        lhs.hatchingProgress == rhs.hatchingProgress &&
        lhs.isHatchingUpload == rhs.isHatchingUpload &&
        lhs.isHatchingOptimizing == rhs.isHatchingOptimizing &&
        lhs.hatchingUploadProgress == rhs.hatchingUploadProgress
    }
}

// Make IncubatingStory conform to GridDisplayable
extension IncubatingStory: GridDisplayable {}

// Dedicated card view for incubating stories
struct IncubatingStoryCard: View {
    let story: IncubatingStory
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    let onDelete: (String) -> Void
    let onHatch: (IncubatingStory, Bool) -> Void
    
    private var progressPercentage: Int {
        guard story.sceneCount > 0 else { return 0 }
        return Int((Double(story.scenesRendered) / Double(story.sceneCount)) * 100)
    }
    
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
                Text("\(progressPercentage)%")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                // Status text
                Text(story.status == "ready" ? "Ready to hatch!" : "Incubating...")
                    .font(.system(size: 14))
                    .foregroundColor(story.status == "ready" ? .green : .white.opacity(0.8))
                
                // Keywords
                if !story.keywords.isEmpty {
                    Text(story.keywords.joined(separator: " • "))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                
                // Hatching progress
                if story.isHatching {
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text(story.hatchingProgress)
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
                
                if story.isHatchingUpload || story.isHatchingOptimizing {
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text(story.isHatchingUpload ? "Uploading \(Int(story.hatchingUploadProgress))%" :
                             story.isHatchingOptimizing ? "Optimizing video..." : "")
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

// Add this class before IncubatingStoriesTabView
class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    @Published var isConnected = true
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
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
    @State private var showSettingsSheet = false
    
    // Story merging states
    @State private var showingStoryPicker = false
    @State private var selectedStoryId: String? = nil
    @State private var isLoadingStoryAssets = false
    @State private var storyMergeProgress: String = ""
    @State private var shouldUpload = false
    
    // Add state for sheet
    @State private var showDescriptionSheet = false
    
    @State private var showingStoreSheet = false
    @State private var showingCreditConfirmation = false
    @State private var pendingKeyframeCount = 4
    @State private var pendingCreditCost = 40
    
    // Add state for keywords in the main view
    @State private var storyKeywords: [String] = ["magical forest", "lost child", "friendly dragon"]
    @State private var newKeyword: String = ""
    
    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-central1")
    
    // Add retry configuration
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0
    
    // Add network error state
    @State private var showNetworkError = false
    
    @StateObject private var networkMonitor = NetworkMonitor()
    
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
    
    private func uploadVideo(from videoURL: URL, description: String, isHatchingMode: Bool = false, storyId: String? = nil) async {
        if isHatchingMode {
            if let storyId = storyId, let index = incubatingStories.firstIndex(where: { $0.id == storyId }) {
                await MainActor.run {
                    incubatingStories[index].isHatchingOptimizing = true
                    incubatingStories[index].hatchingUploadProgress = 0
                }
            }
        } else {
            isOptimizing = true
            uploadProgress = 0
        }
        isDescriptionFocused = false
        
        do {
            let optimizedURL = try await optimizeVideo(from: videoURL)
            
            if isHatchingMode {
                if let storyId = storyId, let index = incubatingStories.firstIndex(where: { $0.id == storyId }) {
                    await MainActor.run {
                        incubatingStories[index].isHatchingOptimizing = false
                        incubatingStories[index].isHatchingUpload = true
                    }
                }
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
                    if let storyId = storyId, let index = self.incubatingStories.firstIndex(where: { $0.id == storyId }) {
                        self.incubatingStories[index].hatchingUploadProgress = progress
                    }
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
        print("🚀 Starting testStoryGeneration - numKeyframes: \(numKeyframes), isFullBuild: \(isFullBuild)")
        isGeneratingStory = true
        
        guard let user = Auth.auth().currentUser else {
            print("❌ Story generation failed: User not authenticated")
            alertMessage = "Please sign in to generate stories"
            isGeneratingStory = false
            showAlert = true
            throw NSError(domain: "StoryGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        print("👤 User authenticated: \(user.uid)")
        
        let callable = functions.httpsCallable("generateStoryFunction")
        let data: [String: Any] = [
            "keywords": storyKeywords,
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
        
        print("📤 Calling Cloud Function with data:", data)
        let result = try await callable.call(data)
        print("📥 Received response:", result.data)
        
        if let resultData = result.data as? [String: Any] {
            storyGenerationResponse = "Story generation successful: \(resultData)"
            print("✅ Story generation successful, response:", resultData)
            
            if let storyId = resultData["storyId"] as? String {
                print("📝 Got storyId: \(storyId), updating Firestore...")
                
                let updateData: [String: Any] = [
                    "status": "incubating",
                    "creator": user.uid,
                    "created_at": Int(Date().timeIntervalSince1970 * 1000),
                    "num_keyframes": numKeyframes,
                    "keywords": storyKeywords,
                    "scenesRendered": 0
                ]
                print("📝 Firestore update data:", updateData)
                
                do {
                    try await db.collection("stories").document(storyId).updateData(updateData)
                    print("✅ Firestore update successful")
                    
                    print("⏳ Waiting for Firestore to update...")
                    try? await Task.sleep(nanoseconds: UInt64(1 * 1_000_000_000))
                    
                    print("🔄 Refreshing stories list...")
                    await loadIncubatingStories()
                    
                    alertMessage = "Story generation completed! Starting asset generation..."
                    showAlert = true
                    isGeneratingStory = false
                    print("✅ Story generation process completed successfully")
                    return storyId
                } catch {
                    print("❌ Firestore update failed:", error)
                    throw error
                }
            } else {
                print("❌ Story ID not found in response")
                throw NSError(domain: "StoryGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Story ID not found in response"])
            }
        } else {
            print("❌ Unexpected response format")
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
                await uploadVideo(from: stitchedURL, description: "Generated Story", isHatchingMode: true, storyId: storyId)
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
                
                if !networkMonitor.isConnected {
                    VStack {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No Internet Connection")
                            .foregroundColor(.gray)
                            .padding(.top)
                        Button("Retry") {
                            Task {
                                await loadIncubatingStories()
                            }
                        }
                        .padding()
                        .background(Color(white: 0.15))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.top)
                    }
                } else if showNetworkError {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.yellow)
                        Text("Connection Error")
                            .foregroundColor(.gray)
                            .padding(.top)
                        Button("Retry") {
                            Task {
                                await loadIncubatingStories()
                            }
                        }
                        .padding()
                        .background(Color(white: 0.15))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.top)
                    }
                } else {
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
                                        let creditCost = numKeyframes * 10
                                        pendingKeyframeCount = numKeyframes
                                        pendingCreditCost = creditCost
                                        showingCreditConfirmation = true
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
                                    
                                    // Settings Button
                                    Button {
                                        showSettingsSheet = true
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: "slider.horizontal.3")
                                                .font(.system(size: 24))
                                            Text("Settings")
                                                .font(.caption)
                                        }
                                        .frame(width: 80)
                                        .padding(.vertical, 12)
                                        .background(Color(white: 0.15))
                                        .cornerRadius(8)
                                    }
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
                                    cardBuilder(story)
                                }
                            )
                        }
                    }
                    .refreshable {
                        await loadIncubatingStories()
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
            .sheet(isPresented: $showSettingsSheet) {
                NavigationView {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        
                        ScrollView {
                            VStack(spacing: 24) {
                                // Story Length Section
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Story Length")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("More scenes create longer, more detailed stories")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    HStack {
                                        Text("\(numKeyframes) scenes")
                                            .foregroundColor(.white)
                                        Spacer()
                                        Stepper("", value: $numKeyframes, in: 2...10, step: 1)
                                            .labelsHidden()
                                    }
                                    .padding(.top, 4)
                                    
                                    Text("\(numKeyframes * 10) credits")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                                
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                
                                // Keywords Input Section
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Story Keywords")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Keywords help shape your story's theme")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    // Keyword Input
                                    HStack {
                                        TextField("Add keyword", text: $newKeyword)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                        
                                        Button(action: {
                                            if !newKeyword.isEmpty {
                                                storyKeywords.append(newKeyword)
                                                newKeyword = ""
                                            }
                                        }) {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundColor(.white)
                                        }
                                        .disabled(newKeyword.isEmpty)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                                
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                
                                // Current Keywords Section
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Current Keywords")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    if storyKeywords.isEmpty {
                                        Text("No keywords added yet")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    } else {
                                        ScrollView {
                                            FlowLayout(spacing: 8) {
                                                ForEach(storyKeywords, id: \.self) { keyword in
                                                    HStack(spacing: 4) {
                                                        Text(keyword)
                                                            .foregroundColor(.white)
                                                        Button {
                                                            storyKeywords.removeAll { $0 == keyword }
                                                        } label: {
                                                            Image(systemName: "xmark.circle.fill")
                                                                .foregroundColor(.white.opacity(0.7))
                                                        }
                                                    }
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color(white: 0.2))
                                                    .cornerRadius(12)
                                                }
                                            }
                                            .padding(.top, 4)
                                        }
                                        .frame(maxHeight: 200)
                                    }
                                }
                                .padding(.horizontal)
                                
                                Spacer()
                            }
                            .padding(.vertical)
                        }
                    }
                    .navigationTitle("Story Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showSettingsSheet = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .alert("Generate Story", isPresented: $showingCreditConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Generate") {
                    Task {
                        // Check if user has enough credits
                        if authService.credits < pendingCreditCost {
                            alertMessage = "Not enough credits! You need \(pendingCreditCost) credits to generate a story with \(pendingKeyframeCount) scenes. Buy more credits to continue."
                            showAlert = true
                            showingStoreSheet = true
                            return
                        }
                        
                        // Try to use credits first
                        let success = await authService.useCredits(pendingCreditCost)
                        if !success {
                            alertMessage = "Failed to use credits. Please try again."
                            showAlert = true
                            return
                        }
                        
                        // Generate the story
                        do {
                            selectedStoryId = try await testStoryGeneration(numKeyframes: pendingKeyframeCount, isFullBuild: true)
                        } catch {
                            // If story generation fails, refund the credits
                            await authService.addCredits(pendingCreditCost)
                            alertMessage = error.localizedDescription
                            showAlert = true
                        }
                    }
                }
            } message: {
                Text("This will use \(pendingCreditCost) credits to generate a story with \(pendingKeyframeCount) scenes. Do you want to continue?")
            }
        }
        .onChange(of: networkMonitor.isConnected) { isConnected in
            if isConnected {
                Task {
                    await loadIncubatingStories()
                }
            }
        }
    }
    
    private func loadIncubatingStories() async {
        print("🔄 Starting loadIncubatingStories")
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ loadIncubatingStories failed: No authenticated user")
            return
        }
        print("👤 Loading stories for user:", userId)
        
        // Set loading state
        await MainActor.run {
            isLoading = true
        }
        
        // Reset network error state
        showNetworkError = false
        
        var retryCount = 0
        while retryCount < maxRetries {
            do {
                print("📚 Querying Firestore - attempt \(retryCount + 1)/\(maxRetries)")
                let query = db.collection("stories")
                    .whereField("creator", isEqualTo: userId)
                    .whereField("status", in: ["incubating", "ready"])
                print("🔍 Query parameters - creator: \(userId), status: [incubating, ready]")
                
                let snapshot = try await query.getDocuments()
                print("📥 Received \(snapshot.documents.count) documents")
                
                let stories = snapshot.documents.compactMap { document -> IncubatingStory? in
                    let data = document.data()
                    print("📄 Processing document \(document.documentID):")
                    print("   Data:", data)
                    
                    return IncubatingStory(
                        id: document.documentID,
                        creator: data["creator"] as? String ?? "",
                        created_at: Double(data["created_at"] as? Int ?? 0),
                        numKeyframes: data["num_keyframes"] as? Int ?? 0,
                        status: data["status"] as? String ?? "",
                        scenesRendered: data["scenesRendered"] as? Int ?? 0,
                        sceneCount: data["sceneCount"] as? Int ?? 0,
                        keywords: data["keywords"] as? [String] ?? []
                    )
                }
                
                let sortedStories = stories.sorted { $0.created_at > $1.created_at }
                print("📊 Processed \(stories.count) valid stories")
                
                await MainActor.run {
                    incubatingStories = sortedStories
                    isLoading = false
                }
                print("✅ Stories loaded successfully")
                return
                
            } catch {
                print("❌ Firestore query failed - attempt \(retryCount + 1):", error)
                retryCount += 1
                if retryCount < maxRetries {
                    print("⏳ Waiting \(retryDelay) seconds before retry...")
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                } else {
                    print("❌ All retry attempts failed")
                    await MainActor.run {
                        showNetworkError = true
                        isLoading = false
                    }
                }
            }
        }
    }
    
    private func deleteStory(_ storyId: String) async {
        print("🗑 Attempting to delete story:", storyId)
        do {
            // Update story status to deleted
            try await db.collection("stories").document(storyId).updateData([
                "status": "deleted",
                "deleted_at": Int(Date().timeIntervalSince1970 * 1000)
            ])
            print("✅ Story marked as deleted")

            // Mark associated assets as deleted
            let batch = db.batch()

            // Get and update images
            let imagesQuery = db.collection("images").whereField("storyId", isEqualTo: storyId)
            let imagesDocs = try await imagesQuery.getDocuments()
            for doc in imagesDocs.documents {
                batch.updateData([
                    "status": "deleted",
                    "deleted_at": Int(Date().timeIntervalSince1970 * 1000)
                ], forDocument: doc.reference)
            }

            // Get and update motion videos
            let motionQuery = db.collection("motion_videos").whereField("storyId", isEqualTo: storyId)
            let motionDocs = try await motionQuery.getDocuments()
            for doc in motionDocs.documents {
                batch.updateData([
                    "status": "deleted",
                    "deleted_at": Int(Date().timeIntervalSince1970 * 1000)
                ], forDocument: doc.reference)
            }

            // Get and update audio files
            let audioQuery = db.collection("audio").whereField("storyId", isEqualTo: storyId)
            let audioDocs = try await audioQuery.getDocuments()
            for doc in audioDocs.documents {
                batch.updateData([
                    "status": "deleted",
                    "deleted_at": Int(Date().timeIntervalSince1970 * 1000)
                ], forDocument: doc.reference)
            }

            // Commit all the updates in one batch
            try await batch.commit()
            print("✅ Associated assets marked as deleted")

            print("🔄 Refreshing stories list...")
            await loadIncubatingStories()
        } catch {
            print("❌ Error deleting story:", error)
            alertMessage = "Failed to delete story: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func hatchStory(_ story: IncubatingStory, shouldUpload: Bool) async {
        // Update the story's hatching state
        if let index = incubatingStories.firstIndex(where: { $0.id == story.id }) {
            await MainActor.run {
                incubatingStories[index].isHatching = true
                incubatingStories[index].hatchingProgress = "Loading story assets..."
            }
        }
        
        do {
            let stitchedURL = try await VideoMerger.mergeStoryAssets(
                storyId: story.id,
                useMotion: true,
                progressCallback: { message in
                    Task { @MainActor in
                        if let index = incubatingStories.firstIndex(where: { $0.id == story.id }) {
                            incubatingStories[index].hatchingProgress = message
                        }
                    }
                }
            )
            
            if shouldUpload {
                if let index = incubatingStories.firstIndex(where: { $0.id == story.id }) {
                    await MainActor.run {
                        incubatingStories[index].isHatchingOptimizing = true
                    }
                }
                // Upload the stitched video with hatching flag
                await uploadVideo(from: stitchedURL, description: "Hatched Story", isHatchingMode: true, storyId: story.id)
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
            
            // Mark story as hatched in Firestore
            try await db.collection("stories").document(story.id).updateData([
                "status": "hatched",
                "hatched_at": Int(Date().timeIntervalSince1970 * 1000)
            ])
            print("✅ Story marked as hatched")
            
            // Reset the story's hatching state
            if let index = incubatingStories.firstIndex(where: { $0.id == story.id }) {
                await MainActor.run {
                    incubatingStories[index].isHatching = false
                    incubatingStories[index].hatchingProgress = ""
                    incubatingStories[index].isHatchingUpload = false
                    incubatingStories[index].isHatchingOptimizing = false
                    incubatingStories[index].hatchingUploadProgress = 0
                }
            }
            
            // Refresh the stories list to remove the hatched story
            await loadIncubatingStories()
            
        } catch {
            alertMessage = "Failed to hatch story: \(error.localizedDescription)"
            // Reset the story's hatching state on error
            if let index = incubatingStories.firstIndex(where: { $0.id == story.id }) {
                await MainActor.run {
                    incubatingStories[index].isHatching = false
                    incubatingStories[index].hatchingProgress = ""
                    incubatingStories[index].isHatchingUpload = false
                    incubatingStories[index].isHatchingOptimizing = false
                    incubatingStories[index].hatchingUploadProgress = 0
                }
            }
        }
        
        showAlert = true
    }
    
    private func cardBuilder(_ story: IncubatingStory) -> some View {
        IncubatingStoryCard(
            story: story,
            showAlert: $showAlert,
            alertMessage: $alertMessage,
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
}

// Add FlowLayout for keyword tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, frame) in result.frames {
            subviews[index].place(at: frame.origin, proposal: ProposedViewSize(frame.size))
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [(Int, CGRect)] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            var maxWidth: CGFloat = 0
            
            for (index, subview) in subviews.enumerated() {
                let viewSize = subview.sizeThatFits(.unspecified)
                
                if currentX + viewSize.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append((index, CGRect(x: currentX, y: currentY, width: viewSize.width, height: viewSize.height)))
                lineHeight = max(lineHeight, viewSize.height)
                currentX += viewSize.width + spacing
                maxWidth = max(maxWidth, currentX)
            }
            
            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
} 