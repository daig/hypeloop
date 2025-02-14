//
//  ContentView.swift
//  hypeloop
//
//  Created by David Girardo on 2/3/25.
//

import SwiftUI
import AVKit
import UIKit
import FirebaseFirestore
import FirebaseAuth

struct ContentView: View {
    @State private var videoManager: VideoManager?
    @State private var selectedTab = 0
    @Binding var isLoggedIn: Bool

    // Add a state to trigger the shake alert.
    @State private var showShakeAlert = false

    // Add Firestore reference
    private let db = Firestore.firestore()
    
    private func clearBloomFilter() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        print("🗑️ Attempting to clear bloom filter for user: \(userId)")
        
        do {
            try await db.collection("bloom_filters").document(userId).delete()
            print("✨ Bloom filter cleared successfully")
            
            // Reload the bloom filter and videos if we have a video manager
            if let videoManager = videoManager {
                await videoManager.reloadBloomFilterAndVideos()
            }
        } catch {
            print("❌ Failed to clear bloom filter: \(error.localizedDescription)")
        }
    }

    var body: some View {
        Group {
            if let videoManager = videoManager {
                // Main content when VideoManager is loaded
                ZStack {
                    Group {
                        switch selectedTab {
                        case 0:
                            HomeTabView(videoManager: videoManager)
                        case 1:
                            SavedVideosTabView(videoManager: videoManager)
                        case 2:
                            IncubatingStoriesTabView()
                        case 3:
                            CreateTabView()
                        default:
                            HomeTabView(videoManager: videoManager)
                        }
                    } .animation(.easeInOut, value: selectedTab)
                    
                    NavigationBar(selectedTab: $selectedTab, isLoggedIn: $isLoggedIn)
                }
            } else {
                ProgressView("Loading...")
                    .task { self.videoManager = await VideoManager() }
            }
        }
        .overlay(ShakeResponder().allowsHitTesting(false))
        // Attach an onReceive that listens for shake notifications.
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            print("🎉 ContentView: Received shake notification!")
            Task {
                await clearBloomFilter()
                showShakeAlert = true
            }
        }
        // Display an alert popup when a shake occurs.
        .alert("Feed Reset", isPresented: $showShakeAlert) {
            Button("OK", role: .cancel) { 
                print("👍 ContentView: Alert dismissed")
            }
        } message: {
            Text("Your video feed has been reset! Pull to refresh to see new videos.")
        }
    }
}