import SwiftUI
import PhotosUI
import AVKit
import FirebaseStorage
import AVFoundation
import FirebaseFunctions
import FirebaseAuth
import FirebaseFirestore
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

struct CreateTabView: View {
    // Upload progress states
    @State private var isOptimizing = false
    @State private var uploadProgress: Double = 0.0
    @FocusState private var isDescriptionFocused: Bool
    @State private var isUploading = false
    @State private var uploadComplete = false
    @State private var alertMessage = ""
    @State private var showAlert = false

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
    
    // Shared instances
    private let functions = Functions.functions(region: "us-central1")
    private let db = Firestore.firestore()
    
    // MARK: - View Components
    
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                UploadSectionView(
                    selectedItem: $selectedItem,
                    selectedVideoURL: $selectedVideoURL,
                    description: $description,
                    isUploading: $isUploading,
                    isOptimizing: $isOptimizing,
                    uploadProgress: $uploadProgress,
                    uploadComplete: $uploadComplete,
                    onVideoSelect: handleVideoSelection,
                    onUpload: {
                        guard let videoURL = selectedVideoURL else {
                            print("❌ Error: No video URL selected")
                            return
                        }
                        await uploadVideo(from: videoURL, description: description)
                    }
                )
                
                StoryGenerationView(
                    isGeneratingStory: $isGeneratingStory,
                    selectedStoryId: $selectedStoryId,
                    showAlert: $showAlert,
                    alertMessage: $alertMessage,
                    numKeyframes: numKeyframes,
                    onKeyframesChange: { newValue in
                        numKeyframes = newValue
                    }
                )
                
                StoryMergeView(
                    showingStoryPicker: $showingStoryPicker,
                    selectedStoryId: $selectedStoryId,
                    isLoadingStoryAssets: $isLoadingStoryAssets,
                    storyMergeProgress: $storyMergeProgress,
                    shouldUpload: $shouldUpload,
                    isUploading: $isUploading,
                    isOptimizing: $isOptimizing,
                    uploadProgress: $uploadProgress,
                    onMergeStoryAssets: { useMotion in
                        Task {
                            await mergeStoryAssets(useMotion: useMotion, outputTo: shouldUpload ? .upload : .photos)
                        }
                    }
                )
            }
            .padding(.horizontal)
            .padding(.top, 20)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                mainContent
            }
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .alert("Upload Status", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func handleVideoSelection(_ newItem: PhotosPickerItem?) async {
        // Reset all state when user starts new video selection
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
        print("🎯 getMuxUploadUrl called with:")
        print("  filename: \(filename)")
        print("  fileSize: \(fileSize)")
        print("  contentType: \(contentType)")
        print("  description: \(description)")
        
        let callable = functions.httpsCallable("getVideoUploadUrl")
        
        let data: [String: Any] = [
            "filename": filename,
            "fileSize": fileSize,
            "contentType": contentType,
            "description": description
        ]
        
        print("📡 Calling Cloud Function with data:")
        print(data)
        
        do {
            let result = try await callable.call(data)
            print("✅ Cloud Function response received:")
            print(result.data)
            
            guard let response = try? JSONSerialization.data(withJSONObject: result.data) else {
                print("❌ Failed to serialize response data")
                throw NSError(domain: "MuxUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
            }
            
            let muxResponse = try JSONDecoder().decode(MuxUploadResponse.self, from: response)
            print("✅ Successfully decoded MuxUploadResponse")
            return muxResponse
            
        } catch {
            print("❌ Cloud Function error:")
            print("  Error type: \(type(of: error))")
            print("  Error details: \(error)")
            throw error
        }
    }
    
    private func uploadToMux(videoURL: URL, uploadURL: String) async throws {
        let data = try Data(contentsOf: videoURL)
        
        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "PUT"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        
        let progressDelegate = UploadProgressDelegate { progress in
            self.uploadProgress = progress
        }
        
        let session = URLSession(configuration: .default, delegate: progressDelegate, delegateQueue: nil)
        
        let (_, response) = try await session.upload(for: request, from: data)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "MuxUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
        }
    }
    
    private func uploadVideo(from videoURL: URL, description: String) async {
        print("📤 Starting video upload process")
        print("  Source URL: \(videoURL)")
        print("  Description: \(description)")
        
        isOptimizing = true
        uploadProgress = 0
        isDescriptionFocused = false
        
        do {
            print("🔄 Optimizing video...")
            let optimizedURL = try await optimizeVideo(from: videoURL)
            print("✅ Video optimized successfully")
            print("  Optimized URL: \(optimizedURL)")
            
            isOptimizing = false
            isUploading = true
            
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: optimizedURL.path)
            let fileSize = fileAttributes[FileAttributeKey.size] as? Int ?? 0
            print("📊 File size: \(fileSize) bytes")
            
            print("🎬 Getting Mux upload URL...")
            let muxResponse = try await getMuxUploadUrl(
                filename: optimizedURL.lastPathComponent,
                fileSize: fileSize,
                contentType: "video/mp4",
                description: description
            )
            
            print("✅ Got Mux upload ID: \(muxResponse.uploadId)")
            
            let user = Auth.auth().currentUser!
            print("👤 User info:")
            print("  UID: \(user.uid)")
            print("  DisplayName: \(user.displayName ?? "nil")")
            print("  Email: \(user.email ?? "nil")")
            print("  Provider ID: \(user.providerData.first?.providerID ?? "nil")")
            
            let uid = user.uid
            
            let userIdentifier: String
            if user.providerData.first?.providerID == "apple.com" {
                userIdentifier = user.email ?? user.displayName ?? "Anonymous"
            } else {
                userIdentifier = user.displayName ?? user.email ?? "Anonymous"
            }
            
            let identifierHash = CreatorNameGenerator.generateCreatorHash(userIdentifier)
            let displayName = CreatorNameGenerator.generateDisplayName(from: identifierHash)
            
            print("👤 Creator info:")
            print("  User ID: \(uid)")
            print("  Identifier: \(userIdentifier)")
            print("  Display Name: \(displayName)")
            
            print("💾 Creating Firestore document...")
            try await db.collection("videos").document(muxResponse.uploadId).setData([
                "id": muxResponse.uploadId,
                "creator": uid,
                "display_name": displayName,
                "description": description,
                "created_at": Int(Date().timeIntervalSince1970 * 1000),
                "status": "uploading"
            ])
            print("✅ Firestore document created")
            
            print("📤 Uploading to Mux...")
            try await uploadToMux(videoURL: optimizedURL, uploadURL: muxResponse.uploadUrl)
            print("✅ Upload to Mux complete")
            
            print("🔄 Updating video status...")
            await updateVideoStatus(assetId: muxResponse.uploadId)
            print("✅ Video status updated")
            
            // Clean up temporary files
            print("🧹 Cleaning up temporary files...")
            try? FileManager.default.removeItem(at: optimizedURL)
            try? FileManager.default.removeItem(at: videoURL)
            print("✅ Temporary files cleaned up")
            
            isUploading = false
            uploadProgress = 0
            uploadComplete = true
            self.description = ""
            selectedVideoURL = nil
            
            print("✅ Upload process completed successfully")
            
        } catch {
            print("❌ Upload error: \(error.localizedDescription)")
            print("  Error details: \(error)")
            alertMessage = "Upload failed: \(error.localizedDescription)"
            showAlert = true
            isUploading = false
            isOptimizing = false
            uploadProgress = 0
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
            print("❌ User not authenticated")
            alertMessage = "Please sign in to generate stories"
            isGeneratingStory = false
            showAlert = true
            throw NSError(domain: "StoryGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("✅ User authenticated: \(user.uid)")
        
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
        
        print("📤 Calling Cloud Function with data:", data)
        let result = try await callable.call(data)
        print("📥 Received response:", result.data)
        
        if let resultData = result.data as? [String: Any] {
            storyGenerationResponse = "Story generation successful: \(resultData)"
            
            if let storyId = resultData["storyId"] as? String {
                print("✅ Story generation completed with ID: \(storyId)")
                alertMessage = "Story generation completed! Starting asset generation..."
                showAlert = true
                isGeneratingStory = false
                return storyId
            } else {
                throw NSError(domain: "StoryGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Story ID not found in response"])
            }
        } else {
            alertMessage = "Story generation completed but response format was unexpected"
            print("⚠️ Unexpected response format: \(result.data)")
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
                await uploadVideo(from: stitchedURL, description: "Generated Story")
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
}

 
