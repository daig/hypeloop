import SwiftUI

struct StoryMergeView: View {
    @Binding var showingStoryPicker: Bool
    @Binding var selectedStoryId: String?
    @Binding var isLoadingStoryAssets: Bool
    @Binding var storyMergeProgress: String
    
    let onMergeStoryAssets: () async -> Void
    
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
                Button(action: { Task { await onMergeStoryAssets() } }) {
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
} 