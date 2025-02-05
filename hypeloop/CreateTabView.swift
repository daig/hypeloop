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

struct CreateTabView: View {
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedVideoURL: URL? = nil
    @State private var description: String = ""
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var currentUploadId: String? = nil
    @State private var testResults: [[String: Any]] = []
    @State private var isLoadingTest = false
    @State private var testError: String? = nil
    @State private var currentTestTask: Task<Void, Never>? = nil
    
    // Shared Functions instance
    private let functions = Functions.functions(region: "us-central1")
    
    // Last test timestamp to enforce delay between calls
    @State private var lastTestTimestamp: Date?
    
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
            
            // Test section for listMuxAssets
            VStack(spacing: 10) {
                Button(action: {
                    // Cancel any existing task
                    currentTestTask?.cancel()
                    
                    // Create a new task
                    currentTestTask = Task {
                        await testListMuxAssets()
                    }
                }) {
                    HStack {
                        if isLoadingTest {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isLoadingTest ? "Loading..." : "Test listMuxAssets")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.2, green: 0.3, blue: 0.3),
                                Color(red: 0.3, green: 0.3, blue: 0.4)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                if let error = testError {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 15) {
                        ForEach(testResults.indices, id: \.self) { index in
                            let result = testResults[index]
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Result \(index + 1):")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                ForEach(Array(result.keys.sorted()), id: \.self) { key in
                                    HStack {
                                        Text(key)
                                            .foregroundColor(.gray)
                                        Spacer()
                                        Text("\(String(describing: result[key] ?? "nil"))")
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)
            }
            
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
        
        let (_, response) = try await URLSession.shared.upload(for: request, from: data, delegate: nil)
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
            
            // Update UI
            alertMessage = "Video uploaded successfully! Upload ID: \(muxResponse.uploadId)"
            showAlert = true
            
            // Reset form
            selectedItem = nil
            selectedVideoURL = nil
            description = ""
            
        } catch {
            alertMessage = "Upload failed: \(error.localizedDescription)"
            showAlert = true
        }
        
        isUploading = false
    }
    
    // MARK: - Test Functions
    
    private func testListMuxAssets() async {
        // Prevent multiple calls while already loading
        guard !isLoadingTest else {
            print("⚠️ Test already in progress")
            return
        }
        
        guard isAuthenticated else {
            testError = "Must be authenticated"
            return
        }
        
        // Enforce minimum delay between calls
        if let lastTest = lastTestTimestamp {
            let timeSinceLastTest = Date().timeIntervalSince(lastTest)
            if timeSinceLastTest < 2.0 { // 2 second minimum delay
                let waitTime = 2.0 - timeSinceLastTest
                print("⏳ Waiting \(String(format: "%.1f", waitTime))s before next test...")
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        
        await MainActor.run {
            isLoadingTest = true
            testError = nil
            testResults = []
            lastTestTimestamp = Date()
        }
        
        do {
            print("📡 Starting listMuxAssets test call...")
            
            // Check if task was cancelled
            if Task.isCancelled {
                print("❌ Test was cancelled before making the call")
                return
            }
            
            // Create a new callable for each request
            let callable = functions.httpsCallable("listMuxAssets")
            
            let result = try await callable.call([
                "debug": true,
                "timestamp": Date().timeIntervalSince1970,
                "client": "ios-test",
                "requestId": UUID().uuidString // Add unique request ID
            ])
            
            // Check if task was cancelled
            if Task.isCancelled {
                print("❌ Test was cancelled after receiving response")
                return
            }
            
            print("✅ Received response from listMuxAssets")
            
            if let response = result.data as? [String: Any],
               let data = response["videos"] as? [[String: Any]] {
                print("📊 Successfully parsed \(data.count) results")
                if !Task.isCancelled {
                    await MainActor.run {
                        testResults = data
                    }
                }
            } else {
                let errorMsg = "Invalid response format: \(String(describing: result.data))"
                print("❌ \(errorMsg)")
                if !Task.isCancelled {
                    await MainActor.run {
                        testError = errorMsg
                    }
                }
            }
        } catch {
            print("❌ Test error: \(error.localizedDescription)")
            if let nsError = error as? NSError {
                print("🔍 Error details - Domain: \(nsError.domain), Code: \(nsError.code)")
                if let details = nsError.userInfo["details"] as? [String: Any] {
                    print("📝 Error details: \(details)")
                }
            }
            if !Task.isCancelled {
                await MainActor.run {
                    testError = error.localizedDescription
                }
            }
        }
        
        if !Task.isCancelled {
            await MainActor.run {
                isLoadingTest = false
            }
        }
    }
}

#Preview {
    CreateTabView()
} 