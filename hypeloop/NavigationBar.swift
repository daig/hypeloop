import SwiftUI
import FirebaseAuth

struct NavigationBar: View {
    @Binding var selectedTab: Int
    @Binding var isLoggedIn: Bool
    @StateObject private var authService = AuthService.shared
    
    private func logoutContextMenu() -> some View {
        Button(role: .destructive, action: {
            do {
                try authService.signOut()
                isLoggedIn = false
            } catch {
                print("Error signing out: \(error)")
            }
        }) {
            Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
        }
    }
    
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 60) {
                // Home tab with long-press menu
                NavigationButton(iconName: "house.fill")
                    .onTapGesture { selectedTab = 0 }
                    .foregroundColor(selectedTab == 0 ? .white : .gray)
                    .contextMenu {
                        logoutContextMenu()
                    }
                
                NavigationButton(iconName: "person.circle.fill")
                    .onTapGesture { selectedTab = 1 }
                    .foregroundColor(selectedTab == 1 ? .white : .gray)
                    .contextMenu {
                        logoutContextMenu()
                    }
                
                NavigationButton(iconName: "video.badge.plus")
                    .onTapGesture { selectedTab = 2 }
                    .foregroundColor(selectedTab == 2 ? .white : .gray)
                    .contextMenu {
                        logoutContextMenu()
                    }
            }
            .padding(.vertical, 10)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.black.opacity(0.5), location: 0.05),
                        .init(color: Color.black.opacity(0.8), location: 0.3),
                        .init(color: .black, location: 0.8)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea()
    }
}

struct NavigationButton: View {
    let iconName: String
    
    var body: some View {
        Image(systemName: iconName)
            .imageScale(.large)
            .font(.system(size: 24)) // Make icons slightly larger since they're alone
    }
}

 