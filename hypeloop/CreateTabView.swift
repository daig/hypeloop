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
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedVideoURL: URL? = nil
    @State private var description: String = ""
    @State private var isUploading = false
    @State private var isOptimizing = false
    @State private var uploadProgress: Double = 0.0
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var uploadComplete = false
    @State private var currentUploadId: String? = nil
    @State private var isLoadingVideo = false
    @FocusState private var isDescriptionFocused: Bool
    
    // Shared instances
    private let functions = Functions.functions(region: "us-central1")
    private let db = Firestore.firestore()
    
    // MARK: - View Components
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        if uploadComplete && selectedVideoURL == nil {
                            successSection
                        }
                        
                        if let videoURL = selectedVideoURL {
                            videoPreviewSection
                        } else if !uploadComplete {
                            uploadPromptSection
                        }
                        
                        if isOptimizing || isUploading {
                            progressSection
                        }
                        
                        if selectedVideoURL != nil {
                            descriptionSection
                        }
                        
                        if selectedVideoURL != nil && !uploadComplete {
                            uploadButton
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                }
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
    
    private var uploadPromptSection: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .videos,
            photoLibrary: .shared()
        ) {
            VStack(spacing: 16) {
                if isLoadingVideo {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .frame(width: 80, height: 80)
                } else {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.2, blue: 0.3))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                        )
                }
                
                Text(isLoadingVideo ? "Loading Video..." : "Select a Video")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if !isLoadingVideo {
                    Text("Tap to choose a video from your library")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                await handleVideoSelection(newItem)
            }
        }
        .disabled(isLoadingVideo)
    }
    
    private var videoPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Video")
                .font(.headline)
                .foregroundColor(.white)
            
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
                
                Image(systemName: "video.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(height: 200)
            
            Button(action: {
                selectedItem = nil
                selectedVideoURL = nil
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Change Video")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
    }
    
    private var progressSection: some View {
        VStack(spacing: 16) {
            if isOptimizing {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    
                    Text("Optimizing video...")
                        .foregroundColor(.white)
                        .font(.subheadline)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Uploading...")
                            .foregroundColor(.white)
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(uploadProgress))%")
                            .foregroundColor(.white)
                            .font(.subheadline.bold())
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .purple]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * uploadProgress / 100, height: 8)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding()
        .background(Color(red: 0.15, green: 0.15, blue: 0.2))
        .cornerRadius(12)
    }
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
                .foregroundColor(.white)
            
            TextEditor(text: $description)
                .frame(height: 100)
                .padding(12)
                .background(Color(red: 0.15, green: 0.15, blue: 0.2))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
                .foregroundColor(.white)
                .focused($isDescriptionFocused)
        }
    }
    
    private var successSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Upload Complete!")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Your video has been successfully uploaded")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            PhotosPicker(
                selection: $selectedItem,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                Text("Upload Another Video")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
            .onChange(of: selectedItem) { newItem in
                Task {
                    await handleVideoSelection(newItem)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.15, green: 0.15, blue: 0.2))
        .cornerRadius(12)
    }
    
    private var uploadButton: some View {
        Button(action: { Task { await uploadVideo() } }) {
            HStack {
                if isUploading || isOptimizing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Upload Video")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue,
                        Color.purple
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(selectedVideoURL == nil || description.isEmpty || isUploading || isOptimizing)
        .opacity((selectedVideoURL == nil || description.isEmpty || isUploading || isOptimizing) ? 0.5 : 1)
    }
    
    // MARK: - Helper Functions
    
    private func handleVideoSelection(_ newItem: PhotosPickerItem?) async {
        // Reset all state when user starts new video selection
        selectedVideoURL = nil
        description = ""
        uploadProgress = 0
        isUploading = false
        uploadComplete = false
        currentUploadId = nil
        isLoadingVideo = true  // Set loading state before processing
        
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
        
        // Create AVAssetTrack for video
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        // Get video dimensions and transform
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        // Calculate transformed dimensions
        let transformedSize = naturalSize.applying(preferredTransform)
        let videoIsPortrait = abs(transformedSize.height) > abs(transformedSize.width)
        
        // Choose appropriate export preset based on video orientation
        let exportPreset = videoIsPortrait ? AVAssetExportPreset960x540 : AVAssetExportPreset1280x720
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: exportPreset
        ) else {
            throw NSError(domain: "VideoExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Export the video
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw exportSession.error ?? NSError(domain: "VideoExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
        
        return outputURL
    }
    
    private func getMuxUploadUrl(filename: String, fileSize: Int, contentType: String) async throws -> MuxUploadResponse {
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
    
    private func uploadVideo() async {
        guard let videoURL = selectedVideoURL else { return }
        
        isOptimizing = true
        uploadProgress = 0
        isDescriptionFocused = false  // Dismiss keyboard first, but keep the text
        
        do {
            // Optimize video before upload
            let optimizedURL = try await optimizeVideo(from: videoURL)
            isOptimizing = false
            isUploading = true
            
            // Get file size and prepare for upload
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: optimizedURL.path)
            let fileSize = fileAttributes[FileAttributeKey.size] as? Int ?? 0
            
            // Get Mux upload URL
            let muxResponse = try await getMuxUploadUrl(
                filename: optimizedURL.lastPathComponent,
                fileSize: fileSize,
                contentType: "video/mp4"
            )
            
            print("Got Mux upload ID: \(muxResponse.uploadId)")
            currentUploadId = muxResponse.uploadId
            
            // Create initial Firestore document
            let user = Auth.auth().currentUser!
            print("📱 Debug - User info:")
            print("  DisplayName: \(user.displayName ?? "nil")")
            print("  Email: \(user.email ?? "nil")")
            print("  Provider ID: \(user.providerData.first?.providerID ?? "nil")")
            
            let uid = user.uid
            
            // Get the user identifier for display name generation
            let userIdentifier: String
            if user.providerData.first?.providerID == "apple.com" {
                userIdentifier = user.email ?? user.displayName ?? "Anonymous"
            } else {
                userIdentifier = user.displayName ?? user.email ?? "Anonymous"
            }
            
            // Generate display name from hashed identifier
            let identifierHash = CreatorNameGenerator.generateCreatorHash(userIdentifier)
            let displayName = CreatorNameGenerator.generateDisplayName(from: identifierHash)
            
            print("📱 Debug - Creator info:")
            print("  User ID: \(uid)")
            print("  Identifier: \(userIdentifier)")
            print("  Display Name: \(displayName)")
            
            try await db.collection("videos").document(muxResponse.uploadId).setData([
                "id": muxResponse.uploadId,
                "creator": uid,
                "display_name": displayName,
                "description": description,  // Use the description before clearing it
                "created_at": Int(Date().timeIntervalSince1970 * 1000), // Convert to milliseconds as integer
                "status": "uploading"
            ])
            
            // Upload to Mux
            try await uploadToMux(videoURL: optimizedURL, uploadURL: muxResponse.uploadUrl)
            
            // Update video status
            if let uploadId = currentUploadId {
                await updateVideoStatus(assetId: uploadId, playbackId: uploadId)
            }
            
            // Clean up temporary files
            try? FileManager.default.removeItem(at: optimizedURL)
            try? FileManager.default.removeItem(at: videoURL)
            
            isUploading = false
            uploadProgress = 0
            uploadComplete = true
            description = ""  // Clear description after successful upload
            selectedVideoURL = nil  // Remove video but keep success state
            
        } catch {
            alertMessage = "Upload failed: \(error.localizedDescription)"
            showAlert = true
            isUploading = false
            isOptimizing = false
            uploadProgress = 0
        }
    }
    
    private func updateVideoStatus(assetId: String, playbackId: String) async {
        do {
            try await db.collection("videos").document(assetId).updateData([
                "status": "uploading"
            ])
        } catch {
            print("Error updating video status: \(error.localizedDescription)")
        }
    }
}

 