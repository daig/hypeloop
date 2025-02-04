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
        }
    }
    
    private func convertToMP4(from sourceURL: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("\(UUID().uuidString).mp4")
        
        let asset = AVAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
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
    
    private func uploadVideo() async {
        guard let videoURL = selectedVideoURL else { return }
        
        isUploading = true
        uploadProgress = 0
        
        do {
            // Convert to MP4 if needed
            let uploadURL = try await convertToMP4(from: videoURL)
            
            // Create a reference to Firebase Storage
            let storageRef = Storage.storage().reference()
            // Create a unique name for the video file
            let videoRef = storageRef.child("videos/\(UUID().uuidString).mp4")
            
            // Start the file upload
            let uploadTask = videoRef.putFile(from: uploadURL, metadata: nil) { metadata, error in
                // Clean up the temporary file
                try? FileManager.default.removeItem(at: uploadURL)
                
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