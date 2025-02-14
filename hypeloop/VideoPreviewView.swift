import SwiftUI
import PhotosUI

struct VideoPreviewView: View {
    let onChangeVideo: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Video")
                .font(.headline)
                .foregroundColor(.white)
            
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
                
                Image(systemName: "video.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(height: 200)
            
            Button(action: onChangeVideo) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Change Video")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
    }
} 