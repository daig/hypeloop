//
//  ContentView.swift
//  hypeloop
//
//  Created by David Girardo on 2/3/25.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @State private var videoManager: VideoManager?
    @State private var selectedTab = 0
    @Binding var isLoggedIn: Bool

    // Add a state to trigger the shake alert.
    @State private var showShakeAlert = false

    var body: some View {
        Group {
            if let videoManager = videoManager {
                // Main content when VideoManager is loaded
                ZStack {
                    // Content based on selected tab
                    Group {
                        if selectedTab == 0 {
                            HomeTabView(videoManager: videoManager)
                        } else if selectedTab == 1 {
                            SavedVideosTabView(videoManager: videoManager)
                        } else {
                            CreateTabView()
                        }
                    }
                    .animation(.easeInOut, value: selectedTab)
                    
                    // Navigation Bar Overlay
                    NavigationBar(selectedTab: $selectedTab, isLoggedIn: $isLoggedIn)
                }
            } else {
                // Loading state
                ProgressView("Loading...")
                    .task {
                        // Initialize VideoManager
                        let manager = await VideoManager()
                        self.videoManager = manager
                    }
            }
        }
        // Attach an onReceive that listens for shake notifications.
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            showShakeAlert = true
        }
        // Display an alert popup when a shake occurs.
        .alert("Shake Detected", isPresented: $showShakeAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You shook the device!")
        }
    }
}