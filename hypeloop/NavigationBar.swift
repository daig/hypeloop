import SwiftUI

struct NavigationBar: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 40) {
                NavigationButton(iconName: "house.fill", label: "Home")
                    .onTapGesture { selectedTab = 0 }
                    .foregroundColor(selectedTab == 0 ? .white : .gray)
                NavigationButton(iconName: "magnifyingglass", label: "Search")
                    .onTapGesture { selectedTab = 1 }
                    .foregroundColor(selectedTab == 1 ? .white : .gray)
                NavigationButton(iconName: "bookmark.fill", label: "Saved")
                    .onTapGesture { selectedTab = 2 }
                    .foregroundColor(selectedTab == 2 ? .white : .gray)
                NavigationButton(iconName: "person.fill", label: "Profile")
                    .onTapGesture { selectedTab = 3 }
                    .foregroundColor(selectedTab == 3 ? .white : .gray)
            }
            .padding(.vertical, 10)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }
}

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

#Preview {
    ZStack {
        // Add a dark background to better see the navigation bar
        Color.black.ignoresSafeArea()
        NavigationBar(selectedTab: .constant(0))
    }
} 