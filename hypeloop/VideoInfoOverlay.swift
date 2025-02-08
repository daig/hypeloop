import SwiftUI
import FirebaseFunctions
import FirebaseFirestore

struct VideoInfoOverlay: View {
    let video: VideoItem
    @State private var gifData: Data? = nil
    @State private var isLoadingGif = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Gradient shadow overlay that extends beyond the bottom
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.4),
                                .init(color: .black.opacity(0.5), location: 0.7),
                                .init(color: .black.opacity(0.8), location: 0.95),
                                .init(color: .black.opacity(0.8), location: 1)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: geometry.size.height + 20)
                    .offset(y: 10)
                    .allowsHitTesting(false)
                
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: geometry.size.height * 0.65)
                    
                    // Description container with scroll and fade
                    ZStack(alignment: .bottom) {
                        // Scrollable content
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                // Title/first line with more emphasis
                                Text(firstLine)
                                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                                    .lineSpacing(6)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                
                                // Rest of description
                                if remainingLines.isEmpty == false {
                                    Text(remainingLines)
                                        .font(.system(size: 17, weight: .regular, design: .default))
                                        .lineSpacing(8)
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.white.opacity(0.95))
                                        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.bottom, 32)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                        .frame(maxHeight: geometry.size.height * 0.25)
                        
                        // Fade-out gradient at bottom
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .black.opacity(0),
                                .black.opacity(0.6),
                                .black.opacity(0.9)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                        .allowsHitTesting(false)
                    }
                    
                    // Creator info with slide-up animation
                    HStack(spacing: 12) {
                        // Profile GIF
                        ZStack {
                            if let data = gifData {
                                AnimatedGIFView(gifData: data)
                                    .frame(width: 36, height: 36)
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
                                    .frame(width: 36, height: 36)
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
                        
                        Text("@\(video.display_name)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .transition(.move(edge: .bottom))
                }
            }
        }
        .task {
            await loadCreatorIcon()
        }
    }
    
    // Split description into first line and remaining text
    private var firstLine: String {
        video.description.components(separatedBy: .newlines).first ?? video.description
    }
    
    private var remainingLines: String {
        let lines = video.description.components(separatedBy: .newlines)
        if lines.count > 1 {
            return lines.dropFirst().joined(separator: "\n")
        }
        return ""
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