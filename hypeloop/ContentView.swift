//
//  ContentView.swift
//  hypeloop
//
//  Created by David Girardo on 2/3/25.
//

import SwiftUI
import AVKit

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background Layer
            Color.black.ignoresSafeArea()
            
            // Video Player Layer
            VideoPlayerView()
                .ignoresSafeArea()
            
            // Overlay Elements (excluding bottom nav)
            ZStack {
                // Video Info Overlay at bottom
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("@creator_name")
                            .font(.headline)
                            .bold()
                        Text("Check out this amazing hyperloop concept! 🚄 #future #transportation")
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.6)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.bottom, 90) // Add padding to lift above nav bar
                    .padding(.trailing, 80) // Add padding to avoid overlap with reaction buttons
                }
                
                // Right-side Reaction Panel
                VStack(spacing: 20) {
                    Spacer()
                    ReactionButton(iconName: "video.badge.plus", label: "React", count: nil)
                    ReactionButton(iconName: "heart.fill", label: "Like", count: "127K")
                    ReactionButton(iconName: "arrow.rectanglepath", label: "Related", count: "234")
                    ReactionButton(iconName: "bubble.right.fill", label: "Responses", count: "1.2K")
                    Spacer()
                        .frame(height: 80) // Add space for bottom nav
                }
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
            // Bottom Navigation Bar (always on top)
            VStack {
                Spacer()
                HStack(spacing: 40) {
                    NavigationButton(iconName: "house.fill", label: "Home")
                    NavigationButton(iconName: "magnifyingglass", label: "Search")
                    NavigationButton(iconName: "plus.square", label: "Create")
                    NavigationButton(iconName: "person.fill", label: "Profile")
                }
                .padding(.vertical, 10)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
            .ignoresSafeArea()
        }
    }
}

struct VideoPlayerView: View {
    // Using Apple's sample HLS stream
    private let player = AVPlayer(url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!)
    
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                // Loop the video
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                    player.seek(to: .zero)
                    player.play()
                }
                player.play()
            }
            .onDisappear {
                player.pause()
            }
    }
}

// Helper Views
struct NavigationButton: View {
    let iconName: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: iconName)
                .imageScale(.large)
            Text(label)
                .font(.caption)
        }
        .foregroundColor(.white)
    }
}

struct ReactionButton: View {
    let iconName: String
    let label: String
    let count: String?
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 28))
            if let count = count {
                Text(count)
                    .font(.caption)
                    .bold()
            }
        }
        .foregroundColor(.white)
    }
}

#Preview {
    ContentView()
}
