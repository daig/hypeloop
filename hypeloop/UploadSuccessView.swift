import SwiftUI
import PhotosUI

struct UploadSuccessView: View {
    let selectedItem: Binding<PhotosPickerItem?>
    let onVideoSelect: (PhotosPickerItem?) async -> Void
    
    var body: some View {
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
                selection: selectedItem,
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
            .onChange(of: selectedItem.wrappedValue) { newItem in
                Task {
                    await onVideoSelect(newItem)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.15, green: 0.15, blue: 0.2))
        .cornerRadius(12)
    }
} 