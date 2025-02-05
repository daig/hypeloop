import SwiftUI
import PhotosUI
import AVKit
import FirebaseStorage
import AVFoundation

struct CreateTabView: View {
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedVideoURL: URL? = nil
    @State private var description: String = ""
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var videoList: [StorageVideo] = []
    @State private var isLoadingList = false
    @State private var copiedVideoName: String? = nil
    
    struct StorageVideo: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let size: Int64
        let updatedTime: Date
        var downloadURL: URL?
        var isLoadingURL: Bool = false
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        VStack {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 40))
                            Text("Select Video")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal)
                    .onChange(of: selectedItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                // Create a temporary file URL
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
                    }
                    
                    if let _ = selectedVideoURL {
                        if isUploading {
                            VStack {
                                ProgressView("Uploading...", value: uploadProgress, total: 100)
                                    .progressViewStyle(.linear)
                                    .foregroundColor(.white)
                                Text("\(Int(uploadProgress))%")
                                    .foregroundColor(.white)
                            }
                            .padding()
                        }
                    }
                    
                    TextField("Add description...", text: $description)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .foregroundColor(.white)
                    
                    Button(action: {
                        Task {
                            await uploadVideo()
                        }
                    }) {
                        if isUploading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Upload")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.2, green: 0.2, blue: 0.3),
                                Color(red: 0.3, green: 0.2, blue: 0.4)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .disabled(selectedVideoURL == nil || description.isEmpty || isUploading)
                    
                    Divider()
                        .background(Color.gray)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Uploaded Videos")
                                .foregroundColor(.white)
                                .font(.headline)
                            
                            Spacer()
                            
                            Button(action: {
                                Task {
                                    await loadVideoList()
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal)
                        
                        if isLoadingList {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(videoList) { video in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(video.name)
                                                .foregroundColor(.white)
                                                .font(.subheadline)
                                            Text("Size: \(formatFileSize(video.size))")
                                                .foregroundColor(.gray)
                                                .font(.caption)
                                            Text("Updated: \(formatDate(video.updatedTime))")
                                                .foregroundColor(.gray)
                                                .font(.caption)
                                            
                                            if let url = video.downloadURL {
                                                Button(action: {
                                                    UIPasteboard.general.string = url.absoluteString
                                                    copiedVideoName = video.name
                                                    
                                                    // Reset the copied status after 2 seconds
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                        if copiedVideoName == video.name {
                                                            copiedVideoName = nil
                                                        }
                                                    }
                                                }) {
                                                    HStack {
                                                        Image(systemName: copiedVideoName == video.name ? "checkmark" : "link")
                                                        Text(copiedVideoName == video.name ? "Copied!" : "Copy Download Link")
                                                    }
                                                    .foregroundColor(.blue)
                                                    .font(.caption)
                                                }
                                            } else if video.isLoadingURL {
                                                ProgressView()
                                                    .scaleEffect(0.7)
                                            } else {
                                                Button(action: {
                                                    Task {
                                                        await fetchDownloadURL(for: video)
                                                    }
                                                }) {
                                                    Text("Get Download Link")
                                                        .foregroundColor(.blue)
                                                        .font(.caption)
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.top, 20)
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
            .task {
                await loadVideoList()
            }
        }
    }
    
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func fetchDownloadURL(for video: StorageVideo) async {
        guard let index = videoList.firstIndex(where: { $0.id == video.id }) else { return }
        
        // Set loading state
        videoList[index].isLoadingURL = true
        
        let storageRef = Storage.storage().reference()
        let videoRef = storageRef.child(video.path)
        
        do {
            let url = try await videoRef.downloadURL()
            videoList[index].downloadURL = url
        } catch {
            print("Error getting download URL: \(error.localizedDescription)")
        }
        
        videoList[index].isLoadingURL = false
    }
    
    private func loadVideoList() async {
        isLoadingList = true
        defer { isLoadingList = false }
        
        let storageRef = Storage.storage().reference()
        let videosRef = storageRef.child("videos")
        
        do {
            let result = try await videosRef.listAll()
            var videos: [StorageVideo] = []
            
            for item in result.items {
                let metadata = try await item.getMetadata()
                let video = StorageVideo(
                    name: item.name,
                    path: item.fullPath,
                    size: metadata.size,
                    updatedTime: metadata.updated ?? Date()
                )
                videos.append(video)
            }
            
            // Sort by most recent first
            videoList = videos.sorted { $0.updatedTime > $1.updatedTime }
        } catch {
            print("Error loading video list: \(error.localizedDescription)")
            alertMessage = "Failed to load video list"
            showAlert = true
        }
    }
    
    private func optimizeVideo(from sourceURL: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("\(UUID().uuidString).mp4")
        
        let asset = AVAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1920x1080 // We'll resize in composition
        ) else {
            throw NSError(domain: "VideoExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        // Configure video compression settings
        let compressionDict: [String: Any] = [
            AVVideoAverageBitRateKey: 2_000_000, // 2 Mbps
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC
        ]
        
        // Target dimensions for 19.5:9 aspect ratio (iPhone style)
        let targetWidth: CGFloat = 1080 // Base width
        let targetHeight: CGFloat = 2340 // Maintains 19.5:9 ratio
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: compressionDict
        ]
        
        // Configure audio settings
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000 // 128 kbps
        ]
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        // Create video composition
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw NSError(domain: "VideoExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: targetWidth, height: targetHeight)
        composition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps
        
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        
        // Calculate scaling to fill height while maintaining aspect ratio
        let scaleX = targetWidth / naturalSize.width
        let scaleY = targetHeight / naturalSize.height
        let scale = max(scaleX, scaleY) // Use max to ensure video fills the frame
        
        let scaledWidth = naturalSize.width * scale
        let scaledHeight = naturalSize.height * scale
        let x = (targetWidth - scaledWidth) / 2
        let y = (targetHeight - scaledHeight) / 2
        
        // Create composition instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        
        // Apply transform and scaling
        var finalTransform = transform
        finalTransform = finalTransform.translatedBy(x: x, y: y)
        finalTransform = finalTransform.scaledBy(x: scale, y: scale)
        
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        
        exportSession.videoComposition = composition
        exportSession.shouldOptimizeForNetworkUse = true
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw exportSession.error ?? NSError(domain: "VideoExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
        
        return outputURL
    }
    
    private func uploadVideo() async {
        guard let videoURL = selectedVideoURL else { return }
        
        isUploading = true
        uploadProgress = 0
        
        do {
            // Optimize video before upload
            let optimizedURL = try await optimizeVideo(from: videoURL)
            
            // Create a reference to Firebase Storage
            let storageRef = Storage.storage().reference()
            let videoRef = storageRef.child("videos/\(UUID().uuidString).mp4")
            
            // Start the file upload
            let uploadTask = videoRef.putFile(from: optimizedURL, metadata: nil) { metadata, error in
                // Clean up the temporary files
                try? FileManager.default.removeItem(at: optimizedURL)
                try? FileManager.default.removeItem(at: videoURL)
                
                isUploading = false
                
                if let error = error {
                    alertMessage = "Upload failed: \(error.localizedDescription)"
                    showAlert = true
                    return
                }
                
                // Retrieve the download URL
                videoRef.downloadURL { url, error in
                    if let error = error {
                        alertMessage = "Failed to get download URL: \(error.localizedDescription)"
                        showAlert = true
                        return
                    }
                    if let downloadURL = url {
                        print("Video uploaded successfully: \(downloadURL.absoluteString)")
                        alertMessage = "Video uploaded successfully!"
                        showAlert = true
                        
                        // Reset the form
                        selectedItem = nil
                        selectedVideoURL = nil
                        description = ""
                    }
                }
            }
            
            // Monitor upload progress
            uploadTask.observe(.progress) { snapshot in
                if let progress = snapshot.progress {
                    uploadProgress = progress.fractionCompleted * 100
                }
            }
        } catch {
            isUploading = false
            alertMessage = "Failed to process video: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

#Preview {
    CreateTabView()
} 