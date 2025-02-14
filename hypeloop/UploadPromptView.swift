import SwiftUI
import PhotosUI

struct UploadPromptView: View {
    let selectedItem: Binding<PhotosPickerItem?>
    let isLoadingVideo: Bool
    
    var body: some View {
        PhotosPicker(
            selection: selectedItem,
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
        .disabled(isLoadingVideo)
    }
} 