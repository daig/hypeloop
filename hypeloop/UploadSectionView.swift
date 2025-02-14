import SwiftUI
import PhotosUI

struct UploadSectionView: View {
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var selectedVideoURL: URL?
    @Binding var description: String
    @Binding var isUploading: Bool
    @Binding var isOptimizing: Bool
    @Binding var uploadProgress: Double
    @Binding var uploadComplete: Bool
    let onVideoSelect: (PhotosPickerItem?) async -> Void
    let onUpload: () async -> Void
    
    var body: some View {
        VStack {
            if uploadComplete && selectedVideoURL == nil {
                UploadSuccessView(
                    selectedItem: $selectedItem,
                    onVideoSelect: { newItem in
                        Task { await onVideoSelect(newItem) }
                    }
                )
            }
            
            if let videoURL = selectedVideoURL {
                VideoPreviewView(onChangeVideo: {
                    selectedItem = nil
                    selectedVideoURL = nil
                })
            } else if !uploadComplete {
                UploadPromptView(
                    selectedItem: $selectedItem,
                    isLoadingVideo: isUploading
                )
                .onChange(of: selectedItem) { newItem in
                    Task { await onVideoSelect(newItem) }
                }
            }
            
            if isOptimizing || isUploading {
                UploadProgressView(
                    isOptimizing: isOptimizing,
                    uploadProgress: uploadProgress
                )
            }
            
            if selectedVideoURL != nil {
                DescriptionInputView(description: $description)
            }
            
            if selectedVideoURL != nil && !uploadComplete {
                UploadButtonView(
                    isUploading: isUploading,
                    isOptimizing: isOptimizing,
                    isDisabled: selectedVideoURL == nil || description.isEmpty || isUploading || isOptimizing,
                    onUpload: onUpload
                )
            }
        }
    }
}
