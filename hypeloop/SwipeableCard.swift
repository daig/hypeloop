import SwiftUI

struct SwipeAction {
    let icon: String
    let color: Color
    let rotationDegrees: Double
    let action: () -> Void
}

struct SwipeConfiguration {
    let leftAction: SwipeAction?
    let rightAction: SwipeAction?
    let upAction: SwipeAction?
    let downAction: SwipeAction?
    
    let swipeThreshold: CGFloat
    let maxRotation: Double
    
    init(
        leftAction: SwipeAction? = nil,
        rightAction: SwipeAction? = nil,
        upAction: SwipeAction? = nil,
        downAction: SwipeAction? = nil,
        swipeThreshold: CGFloat = 100,
        maxRotation: Double = 35
    ) {
        self.leftAction = leftAction
        self.rightAction = rightAction
        self.upAction = upAction
        self.downAction = downAction
        self.swipeThreshold = swipeThreshold
        self.maxRotation = maxRotation
    }
}

struct SwipeableCard<Content: View>: View {
    let content: Content
    let configuration: SwipeConfiguration
    
    @GestureState private var dragOffset: CGSize = .zero
    @State private var offset: CGSize = .zero
    
    // Swipe feedback indicator states
    @State private var showLeftIndicator = false
    @State private var showRightIndicator = false
    @State private var showUpIndicator = false
    @State private var showDownIndicator = false
    @State private var upIndicatorOffset: CGFloat = 0
    @State private var downIndicatorOffset: CGFloat = 0
    
    init(configuration: SwipeConfiguration, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.configuration = configuration
    }
    
    var body: some View {
        ZStack {
            content
                .offset(x: offset.width + dragOffset.width,
                       y: offset.height + dragOffset.height)
                .rotationEffect(.degrees(rotationAngle))
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded(onDragEnded)
                )
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: dragOffset)
            
            // Swipe indicators
            if let leftAction = configuration.leftAction {
                SwipeActionIndicator(
                    systemName: leftAction.icon,
                    color: leftAction.color,
                    isShowing: showLeftIndicator,
                    rotationDegrees: leftAction.rotationDegrees
                )
            }
            
            if let rightAction = configuration.rightAction {
                SwipeActionIndicator(
                    systemName: rightAction.icon,
                    color: rightAction.color,
                    isShowing: showRightIndicator,
                    rotationDegrees: rightAction.rotationDegrees
                )
            }
            
            if let upAction = configuration.upAction {
                SwipeActionIndicator(
                    systemName: upAction.icon,
                    color: upAction.color,
                    isShowing: showUpIndicator,
                    offset: upIndicatorOffset,
                    rotationDegrees: upAction.rotationDegrees
                )
            }
            
            if let downAction = configuration.downAction {
                SwipeActionIndicator(
                    systemName: downAction.icon,
                    color: downAction.color,
                    isShowing: showDownIndicator,
                    offset: downIndicatorOffset,
                    rotationDegrees: downAction.rotationDegrees
                )
            }
        }
    }
    
    private var rotationAngle: Double {
        let dragPercentage = Double(dragOffset.width + offset.width) / 300
        return dragPercentage * configuration.maxRotation
    }
    
    private func onDragEnded(_ gesture: DragGesture.Value) {
        let dragWidth = gesture.translation.width
        let dragHeight = gesture.translation.height
        
        // Vertical swipe
        if abs(dragHeight) > configuration.swipeThreshold && abs(dragHeight) > abs(dragWidth) {
            handleVerticalSwipe(isUp: dragHeight < 0)
        }
        // Horizontal swipe
        else if abs(dragWidth) > configuration.swipeThreshold && abs(dragWidth) > abs(dragHeight) {
            handleHorizontalSwipe(isRight: dragWidth > 0)
        }
        // Not swiped far enough: snap back to center
        else {
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.6)) {
                offset = .zero
            }
        }
    }
    
    private func handleVerticalSwipe(isUp: Bool) {
        if isUp, let upAction = configuration.upAction {
            showUpIndicator = true
            withAnimation(.easeOut(duration: 0.3)) {
                offset.height = -500
                upIndicatorOffset = -200
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                upAction.action()
                withAnimation(.none) { offset = .zero }
                withAnimation(.easeOut(duration: 0.2)) { showUpIndicator = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    upIndicatorOffset = 0
                }
            }
        } else if !isUp, let downAction = configuration.downAction {
            showDownIndicator = true
            withAnimation(.easeOut(duration: 0.3)) {
                offset.height = 500
                downIndicatorOffset = 200
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                downAction.action()
                withAnimation(.none) { offset = .zero }
                withAnimation(.easeOut(duration: 0.2)) { showDownIndicator = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    downIndicatorOffset = 0
                }
            }
        }
    }
    
    private func handleHorizontalSwipe(isRight: Bool) {
        let direction: CGFloat = isRight ? 1 : -1
        if isRight, let rightAction = configuration.rightAction {
            showRightIndicator = true
            animateHorizontalSwipe(direction: direction, action: rightAction.action)
        } else if !isRight, let leftAction = configuration.leftAction {
            showLeftIndicator = true
            animateHorizontalSwipe(direction: direction, action: leftAction.action)
        }
    }
    
    private func animateHorizontalSwipe(direction: CGFloat, action: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.3)) {
            offset.width = direction * 500
            offset.height = dragOffset.height
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            action()
            withAnimation(.none) {
                offset = .zero
            }
            withAnimation(.easeOut(duration: 0.2)) {
                showLeftIndicator = false
                showRightIndicator = false
            }
        }
    }
} 