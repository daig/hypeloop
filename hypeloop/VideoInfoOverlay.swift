import SwiftUI
import FirebaseFunctions

struct VideoInfoOverlay: View {
    let video: VideoItem
    @State private var gifData: Data? = nil
    @State private var isLoadingGif = false
    @State private var showDisplayName = false
    
    private let functions = Functions.functions(region: "us-central1")
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Profile GIF
            ZStack {
                if let data = gifData {
                    AnimatedGIFView(gifData: data)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.3),
                                            .white.opacity(0.1)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.3),
                                            .white.opacity(0.1)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .overlay {
                            if isLoadingGif {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                            }
                        }
                }
            }
            
            // Video Info
            VStack(alignment: .leading, spacing: 4) {
                if showDisplayName {
                    Text("@\(video.display_name)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Text(video.description)
                    .font(.system(size: 15, weight: .medium))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .opacity(0.95)
            }
            .foregroundColor(.white)
            .padding(.top, 4)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDisplayName)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())  // Makes entire area tappable
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showDisplayName.toggle()
            }
        }
        .task {
            await loadProfileGif()
        }
    }
    
    private func loadProfileGif() async {
        guard gifData == nil && !isLoadingGif else { return }
        
        isLoadingGif = true
        defer { isLoadingGif = false }
        
        do {
            let callable = functions.httpsCallable("generateProfileGif")
            let data: [String: Any] = [
                "width": 80,  // Double the display size for retina
                "height": 80,
                "frameCount": 30,
                "delay": 100
            ]
            
            let result = try await callable.call(data)
            
            guard let resultData = result.data as? [String: Any],
                  let base64String = resultData["gif"] as? String,
                  let newGifData = Data(base64Encoded: base64String) else {
                return
            }
            
            await MainActor.run {
                self.gifData = newGifData
            }
        } catch {
            print("Failed to load profile GIF: \(error.localizedDescription)")
        }
    }
} 