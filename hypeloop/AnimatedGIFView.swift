import SwiftUI
import ImageIO

/// A SwiftUI view that displays an animated GIF.
/// Usage:
/// ```swift
/// if let gifData = data {
///     AnimatedGIFView(gifData: gifData)
///         .frame(width: 200, height: 200)
/// }
/// ```
public struct AnimatedGIFView: UIViewRepresentable {
    /// The raw GIF data to animate
    let gifData: Data
    
    /// Optional configuration for the GIF display
    public struct Configuration {
        let contentMode: UIView.ContentMode
        let repeatCount: Int // 0 means infinite
        
        public static let `default` = Configuration(
            contentMode: .scaleAspectFit,
            repeatCount: 0
        )
    }
    
    let configuration: Configuration
    
    /// Initialize with GIF data and optional configuration
    /// - Parameters:
    ///   - gifData: The raw GIF data to display
    ///   - configuration: Display configuration (optional)
    public init(
        gifData: Data,
        configuration: Configuration = .default
    ) {
        self.gifData = gifData
        self.configuration = configuration
    }
    
    public func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = configuration.contentMode
        
        // Create source from data
        guard let source = CGImageSourceCreateWithData(gifData as CFData, nil) else {
            return imageView
        }
        
        let count = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        var duration: TimeInterval = 0
        
        // Extract all frames and their durations
        for i in 0..<count {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                let image = UIImage(cgImage: cgImage)
                images.append(image)
                
                // Get frame duration
                if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                   let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                    
                    if let delayTime = gifProperties[kCGImagePropertyGIFDelayTime as String] as? Double {
                        duration += delayTime
                    }
                }
            }
        }
        
        // Create and start the animation
        imageView.animationImages = images
        imageView.animationDuration = duration
        imageView.animationRepeatCount = configuration.repeatCount
        imageView.startAnimating()
        
        return imageView
    }
    
    public func updateUIView(_ uiView: UIImageView, context: Context) {
        // No update needed as we recreate the view when data changes
    }
}

// MARK: - Convenience Extensions

public extension AnimatedGIFView {
    /// Creates an AnimatedGIFView with a specific content mode
    /// - Parameter mode: The desired content mode for the GIF
    /// - Returns: A new AnimatedGIFView with the specified content mode
    func contentMode(_ mode: UIView.ContentMode) -> AnimatedGIFView {
        AnimatedGIFView(
            gifData: gifData,
            configuration: Configuration(
                contentMode: mode,
                repeatCount: configuration.repeatCount
            )
        )
    }
    
    /// Creates an AnimatedGIFView with a specific repeat count
    /// - Parameter count: Number of times to repeat (0 for infinite)
    /// - Returns: A new AnimatedGIFView with the specified repeat count
    func repeatCount(_ count: Int) -> AnimatedGIFView {
        AnimatedGIFView(
            gifData: gifData,
            configuration: Configuration(
                contentMode: configuration.contentMode,
                repeatCount: count
            )
        )
    }
} 