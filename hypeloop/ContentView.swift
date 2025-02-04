//
//  ContentView.swift
//  hypeloop
//
//  Created by David Girardo on 2/3/25.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var videoManager = VideoManager()
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            // Content based on selected tab
            Group {
                if selectedTab == 0 {
                    HomeTabView(videoManager: videoManager)
                } else if selectedTab == 1 {
                    SearchTabView()
                } else if selectedTab == 2 {
                    SavedVideosTabView(videoManager: videoManager)
                } else {
                    ProfileTabView()
                }
            }
            .animation(.easeInOut, value: selectedTab)
            
            // Navigation Bar Overlay
            NavigationBar(selectedTab: $selectedTab)
        }
    }
}

#Preview {
    ContentView()
}
