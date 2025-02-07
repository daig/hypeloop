import SwiftUI
import FirebaseFunctions
import FirebaseFirestore

struct VideoInfoOverlay: View {
    let video: VideoItem
    @State private var gifData: Data? = nil
    @State private var isLoadingGif = false
    @State private var showDisplayName = false
    
    private let db = Firestore.firestore()
    
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
                                    )
                                )
                        )
                } else {
                    Circle()
                        .fill(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                        .frame(width: 44, height: 44)
                        .overlay(
                            ZStack {
                                if isLoadingGif {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.7)
                                }
                            }
                        )
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
            await loadCreatorIcon()
        }
    }
    
    private func loadCreatorIcon() async {
        guard gifData == nil && !isLoadingGif else { return }
        
        isLoadingGif = true
        defer { isLoadingGif = false }
        
        do {
            // Fetch creator's icon from Firestore
            let docSnapshot = try await db.collection("user_icons").document(video.creator).getDocument()
            
            if let iconData = docSnapshot.data()?["icon_data"] as? String,
               let data = Data(base64Encoded: iconData) {
                await MainActor.run {
                    self.gifData = data
                }
            }
        } catch {
            print("Failed to load creator icon: \(error.localizedDescription)")
        }
    }
} 