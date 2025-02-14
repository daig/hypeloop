import SwiftUI

struct UploadProgressView: View {
    let isOptimizing: Bool
    let uploadProgress: Double
    
    var body: some View {
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
} 