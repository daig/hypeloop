//
//  ContentView.swift
//  hypeloop
//
//  Created by David Girardo on 2/3/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            // Background/Video Layer
            Image("hypeloopBg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
            
            // Content Overlay
            VStack {
                Spacer() // Pushes content to bottom
                
                // Video Info Overlay
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
                        gradient: Gradient(colors: [.clear, .black.opacity(0.3)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Bottom Navigation Bar
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
            
            // Right-side Reaction Panel
            VStack(spacing: 20) {
                Spacer()
                ReactionButton(iconName: "video.badge.plus", label: "React", count: nil)
                ReactionButton(iconName: "heart.fill", label: "Like", count: "127K")
                ReactionButton(iconName: "arrow.rectanglepath", label: "Related", count: "234")
                ReactionButton(iconName: "bubble.right.fill", label: "Responses", count: "1.2K")
                Spacer()
            }
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .trailing)
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
