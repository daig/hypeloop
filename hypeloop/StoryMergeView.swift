import SwiftUI

struct StoryMergeView: View {
    @Binding var showingStoryPicker: Bool
    @Binding var selectedStoryId: String?
    @Binding var isLoadingStoryAssets: Bool
    @Binding var storyMergeProgress: String
    @Binding var shouldUpload: Bool
    @Binding var isUploading: Bool  // Add binding for upload state
    @Binding var isOptimizing: Bool  // Add binding for optimization state
    @Binding var uploadProgress: Double  // Add binding for upload progress
    @State private var useMotion: Bool = true  // Default to true for motion files
    
    let onMergeStoryAssets: (Bool) async -> Void  // Updated to take useMotion parameter
    
    var body: some View {
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
            
            if isLoadingStoryAssets || isUploading || isOptimizing {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text(isUploading ? "Uploading \(Int(uploadProgress))%" :
                         isOptimizing ? "Optimizing video..." :
                         storyMergeProgress)
                        .foregroundColor(.white)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(red: 0.2, green: 0.2, blue: 0.3))
                .cornerRadius(12)
            }
            
            if selectedStoryId != nil && !isLoadingStoryAssets {
                Toggle(isOn: $useMotion) {
                    HStack {
                        Image(systemName: useMotion ? "video.fill" : "photo.fill")
                        Text(useMotion ? "Use Motion Videos" : "Use Static Images")
                    }
                    .foregroundColor(.white)
                }
                .tint(.blue)
                .padding(.horizontal)
                
                Toggle(isOn: $shouldUpload) {
                    HStack {
                        Image(systemName: shouldUpload ? "icloud.and.arrow.up.fill" : "photo.fill")
                        Text(shouldUpload ? "Upload Video" : "Save to Photos")
                    }
                    .foregroundColor(.white)
                }
                .tint(.blue)
                .padding(.horizontal)
                
                Button(action: { Task { await onMergeStoryAssets(useMotion) } }) {
                    HStack {
                        Image(systemName: "arrow.triangle.merge")
                        Text("Merge Story")
                        Text(useMotion ? "(Motion)" : "(Static)")
                            .font(.caption)
                            .opacity(0.8)
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
} 