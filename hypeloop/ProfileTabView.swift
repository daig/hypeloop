import SwiftUI

struct ProfileTabView: View {
    var body: some View {
        Color.black.ignoresSafeArea()
            .overlay(Text("Profile").foregroundColor(.white))
    }
}

#Preview {
    ProfileTabView()
} 