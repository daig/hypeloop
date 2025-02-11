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
import UniformTypeIdentifiers

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
    
    // New state variables for file importing and merging
    @State private var showingFilePicker = false
    @State private var sandboxVideoURL: URL? = nil
    @State private var sandboxAudioURL: URL? = nil
    @State private var isMerging = false
    
    // Add new state for tracking which type of file we're picking
    private enum FilePickerType {
        case video
        case audio
        case both
        
        var contentTypes: [UTType] {
            switch self {
                case .video: return [UTType("public.mpeg-4")!, UTType("public.movie")!, UTType("com.apple.quicktime-movie")!]
                case .audio: return [UTType("public.mp3")!]
                case .both: return [UTType("public.mp3")!, UTType("public.mpeg-4")!]
            }
        }
        
        var allowsMultiple: Bool {
            self == .both
        }
    }
    
    @State private var currentPickerType: FilePickerType?
    
    // Add these state variables at the top with other @State variables
    @State private var isProcessingPairs = false
    @State private var testPairs: [(videoURL: URL, audioURL: URL)] = []
    @State private var showingFolderPicker = false
    
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
                        
                        // New section for file operations
                        fileOperationsSection
                        
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
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: currentPickerType?.contentTypes ?? [],
            allowsMultipleSelection: currentPickerType?.allowsMultiple ?? false
        ) { result in
            print("📁 File picker triggered for type: \(String(describing: currentPickerType))")
            Task {
                switch currentPickerType {
                case .video:
                    if case .success(let urls) = result, let url = urls.first {
                        print("📹 Selected video URL: \(url)")
                        await handleSandboxVideoSelection(.success(url))
                    }
                case .audio:
                    if case .success(let urls) = result, let url = urls.first {
                        print("🎵 Selected audio URL: \(url)")
                        await handleAudioSelection(.success(url))
                    }
                case .both:
                    await handleFileImport(result)
                case .none:
                    print("❌ No picker type set")
                }
                
                if case .failure(let error) = result {
                    print("❌ File picker error: \(error)")
                }
                
                // Reset picker type after selection
                currentPickerType = nil
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
    
    // New section for file operations
    private var fileOperationsSection: some View {
        VStack(spacing: 16) {
            // Import files button
            Button(action: {
                print("📁 Import button tapped")
                currentPickerType = .both
                showingFilePicker = true
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import Files to Sandbox")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(red: 0.2, green: 0.2, blue: 0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            
            // Merge files section
            VStack(spacing: 12) {
                Text("Merge Audio & Video")
                    .font(.headline)
                    .foregroundColor(.white)
                
                // Select video button
                Button(action: { 
                    print("🎬 Video button tapped")
                    currentPickerType = .video
                    showingFilePicker = true
                    print("🎬 showingFilePicker set to: \(showingFilePicker), type: \(String(describing: currentPickerType))")
                }) {
                    HStack {
                        Image(systemName: "video.fill")
                        Text(sandboxVideoURL != nil ? "Change Video" : "Select Video")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.3))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                // Select audio button
                Button(action: { 
                    print("🎵 Audio button tapped")
                    currentPickerType = .audio
                    showingFilePicker = true
                    print("🎵 showingFilePicker set to: \(showingFilePicker), type: \(String(describing: currentPickerType))")
                }) {
                    HStack {
                        Image(systemName: "music.note")
                        Text(sandboxAudioURL != nil ? "Change Audio" : "Select Audio")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.3))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                // Add this inside fileOperationsSection, before the merge files section
                Button(action: {
                    print("📁 Folder picker button tapped")
                    currentPickerType = .both
                    showingFolderPicker = true
                }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Process Folder")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .fileImporter(
                    isPresented: $showingFolderPicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    Task {
                        await processFolderSelection(result)
                    }
                }
                
                // Merge button
                if sandboxVideoURL != nil && sandboxAudioURL != nil {
                    Button(action: { Task { await mergeFiles() } }) {
                        HStack {
                            if isMerging {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "arrow.triangle.merge")
                                Text("Merge Files")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isMerging)
                }
            }
            .padding()
            .background(Color(red: 0.15, green: 0.15, blue: 0.2))
            .cornerRadius(12)
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
    
    // New file handling functions
    private func handleFileImport(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else {
                    print("🚫 Failed to access security scoped resource for: \(url)")
                    continue
                }
                
                defer { url.stopAccessingSecurityScopedResource() }
                
                let filename = url.lastPathComponent
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsURL.appendingPathComponent(filename)
                
                // Remove existing file if it exists
                try? FileManager.default.removeItem(at: destinationURL)
                
                // Copy file to app sandbox
                try FileManager.default.copyItem(at: url, to: destinationURL)
                print("✅ Successfully imported: \(filename)")
            }
            
            alertMessage = "Files imported successfully"
            showAlert = true
            
        } catch {
            print("❌ Error importing files: \(error)")
            alertMessage = "Failed to import files: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func handleSandboxVideoSelection(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            print("📹 Attempting to access video at: \(url)")
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ Failed to access security scoped resource for video")
                throw NSError(domain: "FileAccess", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to access video file"])
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Copy to app sandbox
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filename = url.lastPathComponent
            let destinationURL = documentsURL.appendingPathComponent(filename)
            
            // Remove existing file if it exists
            try? FileManager.default.removeItem(at: destinationURL)
            
            // Copy file to app sandbox
            try FileManager.default.copyItem(at: url, to: destinationURL)
            print("✅ Successfully copied video to: \(destinationURL)")
            
            sandboxVideoURL = destinationURL
            print("✅ Successfully set sandbox video URL")
        } catch {
            print("❌ Error handling video selection: \(error)")
            alertMessage = "Failed to select video: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func handleAudioSelection(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "FileAccess", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to access audio file"])
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Copy to app sandbox
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filename = url.lastPathComponent
            let destinationURL = documentsURL.appendingPathComponent(filename)
            
            // Remove existing file if it exists
            try? FileManager.default.removeItem(at: destinationURL)
            
            // Copy file to app sandbox
            try FileManager.default.copyItem(at: url, to: destinationURL)
            print("✅ Successfully copied audio to: \(destinationURL)")
            
            sandboxAudioURL = destinationURL
            print("✅ Successfully set sandbox audio URL")
        } catch {
            alertMessage = "Failed to select audio: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func mergeFiles() async {
        guard let videoURL = sandboxVideoURL,
              let audioURL = sandboxAudioURL else { return }
        
        isMerging = true
        
        do {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let outputURL = documentsURL.appendingPathComponent("merged_\(UUID().uuidString).mp4")
            
            _ = try await VideoMerger.mergeAudioIntoVideo(
                videoURL: videoURL,
                audioURL: audioURL,
                outputURL: outputURL
            )
            
            // Save to Photos library
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: outputURL, options: nil)
            }
            
            alertMessage = "Files merged successfully! The video has been saved to your Photos library."
            showAlert = true
            
            // Clean up files
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: audioURL)
            
            // Reset selection
            sandboxVideoURL = nil
            sandboxAudioURL = nil
            
        } catch {
            print("❌ Merge error: \(error)")
            alertMessage = "Failed to merge files: \(error.localizedDescription)"
            showAlert = true
        }
        
        isMerging = false
    }
    
    // Add this function with other private functions
    private func processFolderSelection(_ result: Result<[URL], Error>) async {
        do {
            guard let folderURL = try result.get().first else { return }
            
            print("📂 Selected folder: \(folderURL.lastPathComponent)")
            
            guard folderURL.startAccessingSecurityScopedResource() else {
                print("❌ Failed to access folder")
                alertMessage = "Failed to access selected folder"
                showAlert = true
                return
            }
            defer { folderURL.stopAccessingSecurityScopedResource() }
            
            // Get folder contents
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.contentTypeKey],
                options: [.skipsHiddenFiles]
            )
            
            // Function to extract number from filename
            func extractNumber(from filename: String) -> Int? {
                let pattern = "\\d+"  // Match one or more digits
                if let range = filename.range(of: pattern, options: .regularExpression) {
                    return Int(filename[range])
                }
                return nil
            }
            
            // Separate videos and audio files with their numbers
            var numberedVideos: [(number: Int, url: URL)] = []
            var numberedAudios: [(number: Int, url: URL)] = []
            
            for url in contents {
                guard let number = extractNumber(from: url.lastPathComponent) else { continue }
                guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { continue }
                
                if type.conforms(to: .movie) || type.conforms(to: UTType("public.mpeg-4")!) {
                    numberedVideos.append((number, url))
                } else if type.conforms(to: .audio) || type.conforms(to: UTType("public.mp3")!) {
                    numberedAudios.append((number, url))
                }
            }
            
            // Sort by number
            numberedVideos.sort { $0.number < $1.number }
            numberedAudios.sort { $0.number < $1.number }
            
            print("📊 Found \(numberedVideos.count) videos and \(numberedAudios.count) audio files")
            
            // Create pairs by matching numbers
            var pairs: [(videoURL: URL, audioURL: URL)] = []
            var processedNumbers = Set<Int>()
            
            for videoItem in numberedVideos {
                if let matchingAudio = numberedAudios.first(where: { $0.number == videoItem.number }) {
                    if !processedNumbers.contains(videoItem.number) {
                        // Copy files to app sandbox
                        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let videoDestination = documentsURL.appendingPathComponent("temp_\(videoItem.number)_\(videoItem.url.lastPathComponent)")
                        let audioDestination = documentsURL.appendingPathComponent("temp_\(videoItem.number)_\(matchingAudio.url.lastPathComponent)")
                        
                        do {
                            try fileManager.copyItem(at: videoItem.url, to: videoDestination)
                            try fileManager.copyItem(at: matchingAudio.url, to: audioDestination)
                            pairs.append((videoURL: videoDestination, audioURL: audioDestination))
                            processedNumbers.insert(videoItem.number)
                            print("✅ Paired files with number \(videoItem.number)")
                        } catch {
                            print("❌ Error copying files for number \(videoItem.number): \(error)")
                        }
                    }
                } else {
                    print("⚠️ No matching audio found for video number \(videoItem.number)")
                }
            }
            
            if pairs.isEmpty {
                alertMessage = "No valid video-audio pairs found in folder"
                showAlert = true
                return
            }
            
            // Process the pairs and stitch them together
            isProcessingPairs = true
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            do {
                let finalOutputURL = documentsURL.appendingPathComponent("final_stitched_\(UUID().uuidString).mp4")
                
                let stitchedURL = try await VideoMerger.processPairsAndStitch(
                    pairs: pairs,
                    outputURL: finalOutputURL
                )
                
                // Save to Photos library
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .video, fileURL: stitchedURL, options: nil)
                }
                
                print("\n🧹 Cleaning up temporary files...")
                
                // Clean up all files in the documents directory that start with "temp_", "merged_", or "final_stitched_"
                let tempFiles = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
                for fileURL in tempFiles {
                    let filename = fileURL.lastPathComponent
                    if filename.hasPrefix("temp_") || filename.hasPrefix("merged_") || filename.hasPrefix("final_stitched_") {
                        do {
                            try fileManager.removeItem(at: fileURL)
                            print("🗑️ Removed: \(filename)")
                        } catch {
                            print("⚠️ Failed to remove \(filename): \(error)")
                        }
                    }
                }
                
                alertMessage = "Successfully processed and stitched \(pairs.count) pairs into a single video. Saved to Photos."
                print("✅ All temporary files cleaned up")
                
            } catch {
                print("❌ Error processing pairs: \(error)")
                alertMessage = "Error processing pairs: \(error.localizedDescription)"
                
                // Only attempt cleanup of temporary files if there was an error
                print("🧹 Cleaning up temporary files after error...")
                if let tempFiles = try? fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) {
                    for fileURL in tempFiles {
                        let filename = fileURL.lastPathComponent
                        if filename.hasPrefix("temp_") || filename.hasPrefix("merged_") || filename.hasPrefix("final_stitched_") {
                            do {
                                try fileManager.removeItem(at: fileURL)
                                print("🗑️ Removed: \(filename)")
                            } catch {
                                print("⚠️ Failed to remove \(filename): \(error)")
                            }
                        }
                    }
                }
            }
            
            showAlert = true
            isProcessingPairs = false
            
        } catch {
            print("❌ Folder selection error: \(error)")
            alertMessage = "Error selecting folder: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

 