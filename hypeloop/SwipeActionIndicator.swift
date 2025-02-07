import SwiftUI

struct SwipeActionIndicator: View {
    let systemName: String
    let color: Color
    let isShowing: Bool
    let offset: CGFloat
    let rotationDegrees: Double
    
    init(
        systemName: String,
        color: Color,
        isShowing: Bool,
        offset: CGFloat = 0,
        rotationDegrees: Double = 0
    ) {
        self.systemName = systemName
        self.color = color
        self.isShowing = isShowing
        self.offset = offset
        self.rotationDegrees = rotationDegrees
    }
    
    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .frame(width: 100, height: 100)
            .foregroundColor(color)
            .opacity(isShowing ? 0.8 : 0)
            .scaleEffect(isShowing ? 1 : 0.5)
            .rotationEffect(.degrees(rotationDegrees))
            .offset(y: offset)
            .animation(.spring(response: 0.3).speed(0.7), value: isShowing)
            .animation(.interpolatingSpring(stiffness: 40, damping: 8), value: offset)
            .zIndex(3)
    }
} 