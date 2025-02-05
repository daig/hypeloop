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
    @Binding var isLoggedIn: Bool
    
    var body: some View {
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
    }
}

#Preview {
    ContentView(isLoggedIn: .constant(true))
}
