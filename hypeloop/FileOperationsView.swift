import SwiftUI
import UniformTypeIdentifiers

struct FileOperationsView: View {
    @Binding var currentPickerType: FilePickerType?
    @Binding var showingFilePicker: Bool
    @Binding var showingFolderPicker: Bool
    @Binding var sandboxVideoURL: URL?
    @Binding var sandboxAudioURL: URL?
    @Binding var isMerging: Bool
    @Binding var isGeneratingStory: Bool
    @Binding var isFullBuild: Bool
    @Binding var numKeyframes: Int
    
    let onMergeFiles: () async -> Void
    let onTestStoryGeneration: () async -> Void
    let onProcessFolderSelection: (Result<[URL], Error>) async -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Import files button
            // Button(action: {
            //     print("📁 Import button tapped")
            //     currentPickerType = .both
            //     showingFilePicker = true
            // }) {
            //     HStack {
            //         Image(systemName: "square.and.arrow.down")
            //         Text("Import Files to Sandbox")
            //     }
            //     .frame(maxWidth: .infinity)
            //     .padding()
            //     .background(Color(red: 0.2, green: 0.2, blue: 0.3))
            //     .foregroundColor(.white)
            //     .cornerRadius(12)
            // }
            
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

                Button(action: { Task { await onTestStoryGeneration() } }) {
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
                
                // Process folder button
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
                        await onProcessFolderSelection(result)
                    }
                }
                
                // Merge button
                if sandboxVideoURL != nil && sandboxAudioURL != nil {
                    Button(action: { Task { await onMergeFiles() } }) {
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
}

// FilePickerType enum definition
enum FilePickerType {
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
    
    var allowsMultiple: Bool { self == .both }
} 