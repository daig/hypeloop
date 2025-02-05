import SwiftUI
import PhotosUI
import AVKit
import FirebaseStorage
import AVFoundation
import FirebaseFunctions
import FirebaseAuth

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
    @State private var uploadProgress: Double = 0.0
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var currentUploadId: String? = nil
    
    // Shared Functions instance
    private let functions = Functions.functions(region: "us-central1")
    
    private var isAuthenticated: Bool {
        Auth.auth().currentUser != nil
    }
    
    // MARK: - View Components
    
    private var mainContent: some View {
        VStack(spacing: 20) {
            videoPickerButton
                .onChange(of: selectedItem) { newItem in
                    Task {
                        await handleVideoSelection(newItem)
                    }
                }
            
            uploadProgressView
            descriptionField
            uploadButton
            
            Spacer()
        }
        .padding(.top, 20)
    }
    
    private var loginPrompt: some View {
        VStack(spacing: 20) {
            Text("Sign In Required")
                .font(.title2)
                .foregroundColor(.white)
            
            Text("You need to be signed in to upload videos")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            NavigationLink(destination: LoginView(isLoggedIn: .constant(false))) {
                Text("Sign In")
                    .frame(maxWidth: .infinity)
                    .padding()
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
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    private var videoPickerButton: some View {
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
    }
    
    private var uploadProgressView: some View {
        Group {
            if selectedVideoURL != nil && isUploading {
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
    }
    
    private var descriptionField: some View {
        TextField("Add description...", text: $description)
            .textFieldStyle(PlainTextFieldStyle())
            .padding()
            .background(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
            .cornerRadius(8)
            .padding(.horizontal)
            .foregroundColor(.white)
    }
    
    private var uploadButton: some View {
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
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isAuthenticated {
                    mainContent
                } else {
                    loginPrompt
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
    
    // MARK: - Helper Functions
    
    private func handleVideoSelection(_ newItem: PhotosPickerItem?) async {
        guard isAuthenticated else { return }
        
        // Reset progress and upload state when selecting new video
        uploadProgress = 0
        isUploading = false
        
        if let data = try? await newItem?.loadTransferable(type: Data.self) {
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
    
    private func optimizeVideo(from sourceURL: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("\(UUID().uuidString).mp4")
        
        let asset = AVAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1920x1080
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
    
    private func getMuxUploadUrl(filename: String, fileSize: Int, contentType: String) async throws -> MuxUploadResponse {
        guard isAuthenticated else {
            throw NSError(domain: "MuxUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "You must be logged in to upload videos"])
        }
        
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
        guard isAuthenticated else { return }
        
        guard let videoURL = selectedVideoURL else { return }
        
        isUploading = true
        uploadProgress = 0
        
        do {
            // Optimize video before upload
            let optimizedURL = try await optimizeVideo(from: videoURL)
            
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
            
            // Upload to Mux
            try await uploadToMux(videoURL: optimizedURL, uploadURL: muxResponse.uploadUrl)
            
            // Clean up temporary files
            try? FileManager.default.removeItem(at: optimizedURL)
            try? FileManager.default.removeItem(at: videoURL)
            
            // Reset form
            selectedItem = nil
            selectedVideoURL = nil
            description = ""
            isUploading = false
            uploadProgress = 0
            
        } catch {
            alertMessage = "Upload failed: \(error.localizedDescription)"
            showAlert = true
            isUploading = false
            uploadProgress = 0
        }
    }
}

#Preview {
    CreateTabView()
} 