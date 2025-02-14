import SwiftUI

struct DescriptionInputView: View {
    @Binding var description: String
    @FocusState private var isDescriptionFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
                .foregroundColor(.white)
            
            TextEditor(text: $description)
                .frame(height: 100)
                .padding(12)
                .background(Color(red: 0.15, green: 0.15, blue: 0.2))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
                .foregroundColor(.white)
                .focused($isDescriptionFocused)
        }
    }
} 