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
    
    // Story generation test states
    @State private var isGeneratingStory = false
    @State private var storyGenerationResponse: String = ""
    @State private var isFullBuild = false  // Add toggle state
    
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
    
    // Add state variable at the top with other @State variables
    @State private var numKeyframes: Int = 4
    
    // Add new state variables for story merging
    @State private var showingStoryPicker = false
    @State private var selectedStoryId: String? = nil
    @State private var isLoadingStoryAssets = false
    @State private var storyMergeProgress: String = ""
    
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
                        
                        // Add the story merge section
                        storyMergeSection
                        
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
            
            // Test Story Generation Section
            VStack(spacing: 12) {
                Toggle(isOn: $isFullBuild) {
                    Text("Full Build")
                        .foregroundColor(.white)
                }
                .tint(.blue)
                .padding(.horizontal)

                // Add keyframe selector
                Stepper(value: $numKeyframes, in: 1...10) {
                    HStack {
                        Text("Keyframes: \(numKeyframes)")
                            .foregroundColor(.white)
                        Text("(\(numKeyframes * 2) scenes)")
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)

                Button(action: { Task { await testStoryGeneration() } }) {
                    HStack {
                        if isGeneratingStory {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "wand.and.stars")
                            Text(isFullBuild ? "Generate Full Story" : "Test Story Generation")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.purple, .blue]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isGeneratingStory)
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
    
    // Add this new view component after the existing fileOperationsSection
    private var storyMergeSection: some View {
        VStack(spacing: 12) {
            Text("Merge Story Assets")
                .font(.headline)
                .foregroundColor(.white)
            
            Button(action: { showingStoryPicker = true }) {
                HStack {
                    Image(systemName: "book.fill")
                    Text(selectedStoryId != nil ? "Change Story" : "Select Story")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(red: 0.2, green: 0.2, blue: 0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            
            if isLoadingStoryAssets {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text(storyMergeProgress)
                        .foregroundColor(.white)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(red: 0.2, green: 0.2, blue: 0.3))
                .cornerRadius(12)
            }
            
            if selectedStoryId != nil && !isLoadingStoryAssets {
                Button(action: { Task { await mergeStoryAssets() } }) {
                    HStack {
                        Image(systemName: "arrow.triangle.merge")
                        Text("Merge Story")
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
            }
        }
        .padding()
        .background(Color(red: 0.15, green: 0.15, blue: 0.2))
        .cornerRadius(12)
        .sheet(isPresented: $showingStoryPicker) {
            StoryPickerView(selectedStoryId: $selectedStoryId)
        }
    }
    
    // Add this new view for story selection
    struct StoryPickerView: View {
        @Environment(\.dismiss) private var dismiss
        @Binding var selectedStoryId: String?
        @State private var stories: [(id: String, keywords: [String])] = []
        @State private var isLoading = true
        @State private var errorMessage: String?
        
        private let db = Firestore.firestore()
        
        var body: some View {
            NavigationView {
                ZStack {
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                        .ignoresSafeArea()
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    } else if stories.isEmpty {
                        Text("No stories found")
                            .foregroundColor(.white)
                    } else {
                        List(stories, id: \.id) { story in
                            Button(action: {
                                selectedStoryId = story.id
                                dismiss()
                            }) {
                                VStack(alignment: .leading) {
                                    Text("Story ID: \(story.id)")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Keywords: \(story.keywords.joined(separator: ", "))")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                            .listRowBackground(Color(red: 0.2, green: 0.2, blue: 0.3))
                        }
                        .listStyle(.plain)
                    }
                }
                .navigationTitle("Select a Story")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                loadStories()
            }
        }
        
        private func loadStories() {
            guard let userId = Auth.auth().currentUser?.uid else {
                errorMessage = "Please sign in to view stories"
                isLoading = false
                return
            }
            
            db.collection("stories")
                .whereField("userId", isEqualTo: userId)
                .order(by: "created_at", descending: true)
                .getDocuments { snapshot, error in
                    isLoading = false
                    
                    if let error = error {
                        errorMessage = "Error loading stories: \(error.localizedDescription)"
                        return
                    }
                    
                    stories = snapshot?.documents.compactMap { doc -> (id: String, keywords: [String])? in
                        let data = doc.data()
                        guard let keywords = data["keywords"] as? [String] else { return nil }
                        return (id: doc.documentID, keywords: keywords)
                    } ?? []
                }
        }
    }
    
    // Add this new function to handle story asset merging
    private func mergeStoryAssets() async {
        guard let storyId = selectedStoryId else { return }
        isLoadingStoryAssets = true
        storyMergeProgress = "Loading story assets..."
        
        do {
            // Get all audio and image assets for this story
            let audioQuery = db.collection("audio").whereField("storyId", isEqualTo: storyId)
            let imageQuery = db.collection("images").whereField("storyId", isEqualTo: storyId)
            
            let audioSnapshot = try await audioQuery.getDocuments()
            let imageSnapshot = try await imageQuery.getDocuments()
            
            print("📊 Found \(audioSnapshot.documents.count) audio files and \(imageSnapshot.documents.count) images")
            
            // Sort assets by sceneNumber
            let audioAssets = audioSnapshot.documents
                .compactMap { doc -> (sceneNumber: Int, assetId: String?, playbackId: String?, downloadUrl: String?)? in
                    let data = doc.data()
                    guard let sceneNumber = data["sceneNumber"] as? Int else { return nil }
                    let assetId = data["assetId"] as? String
                    let playbackId = data["playbackId"] as? String
                    let downloadUrl = data["download_url"] as? String
                    return (sceneNumber, assetId, playbackId, downloadUrl)
                }
                .sorted { $0.sceneNumber < $1.sceneNumber }
            
            let imageAssets = imageSnapshot.documents
                .compactMap { doc -> (sceneNumber: Int, url: String)? in
                    let data = doc.data()
                    guard let sceneNumber = data["sceneNumber"] as? Int,
                          let url = data["url"] as? String else { return nil }
                    return (sceneNumber, url)
                }
                .sorted { $0.sceneNumber < $1.sceneNumber }
            
            print("🔄 After processing:")
            print("🎵 Audio assets: \(audioAssets.map { $0.sceneNumber })")
            print("🖼️ Image assets: \(imageAssets.map { $0.sceneNumber })")
            
            // Create temporary directory for downloaded files
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Download all assets
            var pairs: [(videoURL: URL, audioURL: URL)] = []
            var downloadedAudioFiles: Set<Int> = []
            var downloadedVideoFiles: Set<Int> = []
            
            // Download audio files
            for asset in audioAssets {
                storyMergeProgress = "Downloading audio \(asset.sceneNumber + 1) of \(audioAssets.count)..."
                let audioURL = tempDir.appendingPathComponent("audio_\(asset.sceneNumber).mp3")
                
                guard let downloadUrl = asset.downloadUrl else {
                    print("⚠️ No download URL found for scene \(asset.sceneNumber)")
                    continue
                }
                
                print("🔍 Starting download for scene \(asset.sceneNumber)")
                print("📍 URL: \(downloadUrl)")
                print("💾 Will save to: \(audioURL.path)")
                
                do {
                    print("⬇️ Downloading data...")
                    let (audioData, response) = try await URLSession.shared.data(from: URL(string: downloadUrl)!)
                    print("📦 Download complete. Received \(audioData.count) bytes")
                    if let httpResponse = response as? HTTPURLResponse {
                        print("🌐 HTTP Status: \(httpResponse.statusCode)")
                        print("🏷️ Content Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "none")")
                    }
                    
                    print("💾 Writing data to disk...")
                    try audioData.write(to: audioURL)
                    print("✅ Successfully wrote file to: \(audioURL.path)")
                    
                    downloadedAudioFiles.insert(asset.sceneNumber)
                    print("✨ Completed processing for scene \(asset.sceneNumber)")
                } catch {
                    print("❌ Error for scene \(asset.sceneNumber):")
                    print("   Error type: \(type(of: error))")
                    print("   Description: \(error.localizedDescription)")
                    if let urlError = error as? URLError {
                        print("   URLError code: \(urlError.code.rawValue)")
                        print("   URLError description: \(urlError)")
                    }
                    continue
                }
            }
            
            // Download and process image files
            for asset in imageAssets {
                storyMergeProgress = "Processing image \(asset.sceneNumber + 1) of \(imageAssets.count)..."
                
                // Download the image
                print("📥 Image download URL for scene \(asset.sceneNumber): \(asset.url ?? "nil")")
                let imageDownloadURL = URL(string: asset.url)!
                let (imageData, _) = try await URLSession.shared.data(from: imageDownloadURL)
                
                // Create video from image
                let videoURL = try await createVideoFromImage(imageData: imageData)
                downloadedVideoFiles.insert(asset.sceneNumber)
                print("✅ Created video for scene \(asset.sceneNumber)")
                
                // Check if we have both audio and video for this scene
                if downloadedAudioFiles.contains(asset.sceneNumber) {
                    let audioURL = tempDir.appendingPathComponent("audio_\(asset.sceneNumber).mp3")
                    if FileManager.default.fileExists(atPath: audioURL.path) {
                        pairs.append((videoURL: videoURL, audioURL: audioURL))
                        print("🔗 Created pair for scene \(asset.sceneNumber)")
                    }
                }
            }
            
            print("👥 Final pairs count: \(pairs.count)")
            print("📂 Downloaded audio files: \(downloadedAudioFiles)")
            print("📂 Created video files: \(downloadedVideoFiles)")
            
            if pairs.isEmpty {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid pairs found. Audio files: \(downloadedAudioFiles.count), Video files: \(downloadedVideoFiles.count)"])
            }
            
            // Process pairs and stitch them together
            storyMergeProgress = "Merging assets..."
            let outputURL = tempDir.appendingPathComponent("final_\(UUID().uuidString).mp4")
            
            let stitchedURL = try await VideoMerger.processPairsAndStitch(
                pairs: pairs,
                outputURL: outputURL
            )
            
            // Save to Photos library
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: stitchedURL, options: nil)
            }
            
            // Clean up
            try FileManager.default.removeItem(at: tempDir)
            
            alertMessage = "Story assets merged successfully! The video has been saved to your Photos library."
            selectedStoryId = nil
            
        } catch {
            alertMessage = "Failed to merge story assets: \(error.localizedDescription)"
        }
        
        showAlert = true
        isLoadingStoryAssets = false
        storyMergeProgress = ""
    }
    
    private func createVideoFromImage(imageData: Data, duration: Double = 3.0) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let videoURL = tempDir.appendingPathComponent("\(UUID().uuidString).mp4")
        
        // Create AVAssetWriter
        let assetWriter = try AVAssetWriter(url: videoURL, fileType: .mp4)
        
        // Create video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 512,
            AVVideoHeightKey: 512,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2000000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        // Create writer input
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = true
        
        // Create pixel buffer adapter
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 512,
            kCVPixelBufferHeightKey as String: 512
        ]
        
        let adapter = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: attributes
        )
        
        assetWriter.add(writerInput)
        try await assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        
        // Create UIImage from data
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image from data"])
        }
        
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        try CVPixelBufferCreate(
            kCFAllocatorDefault,
            512,
            512,
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard let buffer = pixelBuffer else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
        }
        
        // Lock buffer and draw image into it
        CVPixelBufferLockBaseAddress(buffer, [])
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: pixelData,
            width: 512,
            height: 512,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
        }
        
        // Draw image
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        // Write frames
        let frameCount = Int(duration * 24) // 24 fps
        
        // Set up the writer input once, outside the loop
        writerInput.requestMediaDataWhenReady(on: .main) {
            // The block intentionally left empty - we'll handle writing in our loop
        }
        
        for frameNumber in 0..<frameCount {
            let presentationTime = CMTime(value: CMTimeValue(frameNumber), timescale: 24)
            
            // Simple polling with a short sleep
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms sleep
            }
            
            adapter.append(buffer, withPresentationTime: presentationTime)
        }
        
        // Finish writing
        writerInput.markAsFinished()
        await assetWriter.finishWriting()
        
        return videoURL
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
            
            // Function to extract numbers from filename
            func extractNumbers(from filename: String) -> (primary: Int, secondary: Int)? {
                let pattern = "(\\d+)_(\\d+)"  // Match pattern like "1_1"
                if let match = filename.range(of: pattern, options: .regularExpression) {
                    let numbers = filename[match].split(separator: "_")
                    if numbers.count == 2,
                       let primary = Int(numbers[0]),
                       let secondary = Int(numbers[1]) {
                        return (primary, secondary)
                    }
                }
                return nil
            }
            
            // Separate videos and audio files with their numbers
            var numberedVideos: [(primary: Int, secondary: Int, url: URL)] = []
            var numberedAudios: [(primary: Int, secondary: Int, url: URL)] = []
            
            for url in contents {
                guard let numbers = extractNumbers(from: url.lastPathComponent) else { continue }
                guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { continue }
                
                let isVideo = type.conforms(to: .movie) || type.conforms(to: UTType("public.mpeg-4")!)
                let isAudio = type.conforms(to: .audio) || type.conforms(to: UTType("public.mp3")!)
                
                if isVideo && url.lastPathComponent.contains("keyframe") {
                    numberedVideos.append((numbers.primary, numbers.secondary, url))
                } else if isAudio && url.lastPathComponent.contains("voiceover") {
                    numberedAudios.append((numbers.primary, numbers.secondary, url))
                }
            }
            
            // Sort by primary number first, then secondary number
            numberedVideos.sort { 
                if $0.primary != $1.primary {
                    return $0.primary < $1.primary
                }
                return $0.secondary < $1.secondary
            }
            numberedAudios.sort { 
                if $0.primary != $1.primary {
                    return $0.primary < $1.primary
                }
                return $0.secondary < $1.secondary
            }
            
            print("📊 Found \(numberedVideos.count) videos and \(numberedAudios.count) audio files")
            
            // Create pairs by matching both numbers
            var pairs: [(videoURL: URL, audioURL: URL)] = []
            var processedPairs = Set<String>()
            
            for videoItem in numberedVideos {
                if let matchingAudio = numberedAudios.first(where: { 
                    $0.primary == videoItem.primary && $0.secondary == videoItem.secondary 
                }) {
                    let pairKey = "\(videoItem.primary)_\(videoItem.secondary)"
                    if !processedPairs.contains(pairKey) {
                        // Copy files to app sandbox
                        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let videoDestination = documentsURL.appendingPathComponent("temp_\(pairKey)_\(videoItem.url.lastPathComponent)")
                        let audioDestination = documentsURL.appendingPathComponent("temp_\(pairKey)_\(matchingAudio.url.lastPathComponent)")
                        
                        do {
                            try fileManager.copyItem(at: videoItem.url, to: videoDestination)
                            try fileManager.copyItem(at: matchingAudio.url, to: audioDestination)
                            pairs.append((videoURL: videoDestination, audioURL: audioDestination))
                            processedPairs.insert(pairKey)
                            print("✅ Paired files with numbers \(pairKey)")
                        } catch {
                            print("❌ Error copying files for numbers \(pairKey): \(error)")
                        }
                    }
                } else {
                    print("⚠️ No matching audio found for video \(videoItem.primary)_\(videoItem.secondary)")
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
    
    // Add story generation test function
    private func testStoryGeneration() async {
        isGeneratingStory = true
        
        do {
            // Check if user is authenticated
            guard let user = Auth.auth().currentUser else {
                print("❌ User not authenticated")
                alertMessage = "Please sign in to generate stories"
                isGeneratingStory = false
                showAlert = true
                return
            }
            
            print("✅ User authenticated: \(user.uid)")
            
            // Use the correct function name that matches the deployed function
            let callable = functions.httpsCallable("generateStoryFunction")
            
            let data: [String: Any] = [
                "keywords": ["magical forest", "lost child", "friendly dragon"],
                "config": [
                    "extract_chars": true,
                    "generate_voiceover": true,
                    "generate_images": isFullBuild,
                    "generate_motion": isFullBuild,  // Keep motion generation tied to full build
                    "save_script": true,
                    "num_keyframes": numKeyframes,  // Use the selected number of keyframes
                    "output_dir": "output"
                ]
            ]
            
            print("📤 Calling Cloud Function with data:", data)
            let result = try await callable.call(data)
            print("📥 Received response:", result.data)
            
            if let resultData = result.data as? [String: Any] {
                storyGenerationResponse = "Story generation successful: \(resultData)"
                alertMessage = isFullBuild ? 
                    "Full story generation with motion started!" :
                    "Story generation test completed successfully!"
                print("✅ Story generation response: \(resultData)")
            } else {
                alertMessage = "Story generation completed but response format was unexpected"
                print("⚠️ Unexpected response format: \(result.data)")
            }
        } catch {
            print("❌ Story generation error: \(error)")
            if let authError = error as? AuthErrorCode {
                alertMessage = "Authentication error: \(authError.localizedDescription)"
            } else {
                alertMessage = "Story generation failed: \(error.localizedDescription)"
            }
        }
        
        isGeneratingStory = false
        showAlert = true
    }
}

 