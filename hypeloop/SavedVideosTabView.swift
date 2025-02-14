import SwiftUI
import UIKit
import SafariServices
import UniformTypeIdentifiers
import FirebaseFirestore
import FirebaseAuth

struct SavedVideosTabView: View {
    @ObservedObject var videoManager: VideoManager
    @StateObject private var authService = AuthService.shared
    @State private var presentingSafari = false
    @State private var selectedVideoURL: URL? = nil
    @State private var isLoading = true
    @State private var currentPage = 0
    @State private var hasMoreContent = true
    @State private var isLoadingMore = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showingStoreSheet = false
    private let videosPerPage = 20
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // User Profile Section - Now fixed at the top
                    VStack(spacing: 16) {
                        // User Icon
                        if let iconData = authService.userIconData {
                            AnimatedGIFView(gifData: iconData)
                                .frame(width: 100, height: 100)
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
                                .frame(width: 100, height: 100)
                        }
                        
                        // Display Name
                        Text("@\(authService.displayName)")
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)
                        
                        // Credits Section
                        HStack(spacing: 12) {
                            // Credits display
                            VStack(alignment: .center, spacing: 4) {
                                Text("\(authService.credits)")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Credits")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .frame(width: 100)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                            )
                            
                            // Buy Credits Button
                            Button(action: {
                                showingStoreSheet = true
                            }) {
                                HStack {
                                    Image(systemName: "cart.circle.fill")
                                    Text("Buy Credits")
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.2, green: 0.2, blue: 0.3),
                                                    Color(red: 0.3, green: 0.2, blue: 0.4)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 24)
                    
                    // Content Section - Always fills remaining space
                    ScrollView {
                        SavedVideoGridView(
                            items: videoManager.savedVideos,
                            isLoading: isLoading,
                            isLoadingMore: isLoadingMore,
                            hasMoreContent: hasMoreContent,
                            showAlert: $showAlert,
                            alertMessage: $alertMessage,
                            onLoadMore: {
                                Task {
                                    await loadMoreContent()
                                }
                            },
                            cardBuilder: { video in
                                SavedVideoCard(
                                    video: video,
                                    showAlert: $showAlert,
                                    alertMessage: $alertMessage,
                                    videoManager: videoManager
                                )
                            }
                        )
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .sheet(isPresented: $presentingSafari) {
                if let url = selectedVideoURL {
                    SafariView(url: url)
                }
            }
            .task {
                await loadSavedVideos()
            }
            .refreshable {
                await loadSavedVideos()
            }
            .sheet(isPresented: $showingStoreSheet) {
                StoreView()
            }
        }
    }
    
    private func loadSavedVideos() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        currentPage = 0
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("saved_videos")
                .order(by: "saved_at", descending: true)
                .limit(to: videosPerPage)
                .getDocuments()
            
            let videos = snapshot.documents.compactMap { document -> VideoItem? in
                let data = document.data()
                return VideoItem(
                    id: data["id"] as? String ?? "",
                    playback_id: data["playback_id"] as? String ?? "",
                    creator: data["creator"] as? String ?? "",
                    display_name: data["display_name"] as? String ?? "",
                    description: data["description"] as? String ?? "",
                    created_at: Double(data["created_at"] as? Int ?? 0),
                    status: "ready"
                )
            }
            
            hasMoreContent = !snapshot.documents.isEmpty && snapshot.documents.count == videosPerPage
            
            await MainActor.run {
                videoManager.savedVideos = videos
                isLoading = false
            }
        } catch {
            print("Error loading saved videos: \(error.localizedDescription)")
            isLoading = false
        }
    }
    
    private func loadMoreContent() async {
        guard let userId = Auth.auth().currentUser?.uid,
              hasMoreContent && !isLoadingMore,
              !videoManager.savedVideos.isEmpty else { return }
        
        isLoadingMore = true
        
        do {
            let lastVideo = videoManager.savedVideos.last
            let snapshot = try await db.collection("users").document(userId)
                .collection("saved_videos")
                .order(by: "saved_at", descending: true)
                .start(after: [lastVideo?.created_at ?? 0])
                .limit(to: videosPerPage)
                .getDocuments()
            
            let newVideos = snapshot.documents.compactMap { document -> VideoItem? in
                let data = document.data()
                return VideoItem(
                    id: data["id"] as? String ?? "",
                    playback_id: data["playback_id"] as? String ?? "",
                    creator: data["creator"] as? String ?? "",
                    display_name: data["display_name"] as? String ?? "",
                    description: data["description"] as? String ?? "",
                    created_at: Double(data["created_at"] as? Int ?? 0),
                    status: "ready"
                )
            }
            
            hasMoreContent = !snapshot.documents.isEmpty && snapshot.documents.count == videosPerPage
            
            await MainActor.run {
                videoManager.savedVideos.append(contentsOf: newVideos)
                currentPage += 1
                isLoadingMore = false
            }
        } catch {
            print("Error loading more videos: \(error.localizedDescription)")
            isLoadingMore = false
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

 