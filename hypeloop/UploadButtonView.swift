import SwiftUI

struct UploadButtonView: View {
    let isUploading: Bool
    let isOptimizing: Bool
    let isDisabled: Bool
    let onUpload: () async -> Void
    
    var body: some View {
        Button(action: { Task { await onUpload() } }) {
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
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
} 