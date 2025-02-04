import SwiftUI

struct SearchTabView: View {
    var body: some View {
        Color.black.ignoresSafeArea()
            .overlay(Text("Search").foregroundColor(.white))
    }
}

#Preview {
    SearchTabView()
} 
