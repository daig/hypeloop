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
    }
}


