import AVFoundation
import Foundation

enum VideoMergerError: Error {
    case videoTrackNotFound
    case audioTrackNotFound
    case exportSessionCreationFailed
    case exportFailed(Error?)
    case assetCreationFailed
}

class VideoMerger {
    /// Merges an audio file with a video file, replacing the video's original audio track.
    /// If the audio is longer than the video, the video will be stretched to match.
    /// If the video is longer than the audio, the audio will be stretched to match.
    /// - Parameters:
    ///   - videoURL: URL of the video file
    ///   - audioURL: URL of the audio file to merge
    ///   - outputURL: URL where the merged video will be saved
    /// - Returns: URL of the merged video file
    static func mergeAudioIntoVideo(videoURL: URL, audioURL: URL, outputURL: URL) async throws -> URL {
        print("\n📼 Starting video merge process...")
        
        // Create AVAssets
        print("📦 Loading assets...")
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        
        // Load the assets
        try await videoAsset.load(.tracks, .duration)
        try await audioAsset.load(.tracks, .duration)
        
        // Get durations
        let videoDuration = CMTimeGetSeconds(videoAsset.duration)
        let audioDuration = CMTimeGetSeconds(audioAsset.duration)
        print("\n📊 Duration Analysis:")
        print("├─ Video duration: \(String(format: "%.2f", videoDuration))s")
        print("├─ Audio duration: \(String(format: "%.2f", audioDuration))s")
        print("└─ Difference: \(String(format: "%.2f", abs(videoDuration - audioDuration)))s")
        
        // Create composition
        print("\n🎬 Creating composition...")
        let composition = AVMutableComposition()
        
        // Get video track
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("❌ Failed to get video track")
            throw VideoMergerError.videoTrackNotFound
        }
        
        // Get audio track
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("❌ Failed to get audio track")
            throw VideoMergerError.audioTrackNotFound
        }
        
        print("\n🔄 Matching durations...")
        
        // Determine which duration to use (always use the longer duration)
        let targetDuration = max(audioDuration, videoDuration)
        print("├─ Using target duration: \(String(format: "%.2f", targetDuration))s")
        
        // Insert and scale video track
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoAsset.duration),
            of: videoTrack,
            at: .zero
        )
        
        if videoDuration != targetDuration {
            compositionVideoTrack.scaleTimeRange(
                CMTimeRange(start: .zero, duration: videoAsset.duration),
                toDuration: CMTime(seconds: targetDuration, preferredTimescale: 600)
            )
            print("├─ Scaled video to match target duration")
        }
        
        // Insert and scale audio track
        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: audioAsset.duration),
            of: audioTrack,
            at: .zero
        )
        
        if audioDuration != targetDuration {
            compositionAudioTrack.scaleTimeRange(
                CMTimeRange(start: .zero, duration: audioAsset.duration),
                toDuration: CMTime(seconds: targetDuration, preferredTimescale: 600)
            )
            print("└─ Scaled audio to match target duration")
        }
        
        print("\n📤 Exporting final video...")
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            print("❌ Failed to create export session")
            throw VideoMergerError.exportSessionCreationFailed
        }
        
        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Export the file
        await exportSession.export()
        
        // Check export status
        if exportSession.status == .completed {
            print("✅ Export completed successfully")
            print("📁 Saved to: \(outputURL.lastPathComponent)")
            return outputURL
        } else {
            print("❌ Export failed with error: \(String(describing: exportSession.error))")
            throw VideoMergerError.exportFailed(exportSession.error)
        }
    }
    
    /// Process multiple pairs of video and audio files, merge each pair, then stitch all merged videos together
    /// - Parameters:
    ///   - pairs: Array of tuples containing video and audio URLs to merge
    ///   - outputURL: URL where the final stitched video will be saved
    /// - Returns: URL of the final stitched video
    static func processPairsAndStitch(pairs: [(videoURL: URL, audioURL: URL)], outputURL: URL) async throws -> URL {
        print("\n🎬 Starting batch processing and stitching of \(pairs.count) pairs...")
        var mergedFiles: [URL] = []
        
        // First, merge all pairs
        for (index, pair) in pairs.enumerated() {
            print("\n📦 Processing pair \(index + 1) of \(pairs.count)")
            
            do {
                // Create temporary output URL for merged file
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let mergedURL = documentsURL.appendingPathComponent("merged_\(UUID().uuidString).mp4")
                
                // Merge the pair
                let mergedFile = try await mergeAudioIntoVideo(
                    videoURL: pair.videoURL,
                    audioURL: pair.audioURL,
                    outputURL: mergedURL
                )
                
                mergedFiles.append(mergedFile)
                print("✅ Successfully processed pair \(index + 1)")
                
                // Clean up the input files after successful merge
                try? FileManager.default.removeItem(at: pair.videoURL)
                try? FileManager.default.removeItem(at: pair.audioURL)
                print("🗑️ Cleaned up input files for pair \(index + 1)")
                
            } catch {
                print("❌ Error processing pair \(index + 1): \(error)")
                // Clean up the input files even if merge failed
                try? FileManager.default.removeItem(at: pair.videoURL)
                try? FileManager.default.removeItem(at: pair.audioURL)
                print("🗑️ Cleaned up input files for failed pair \(index + 1)")
                continue
            }
        }
        
        if mergedFiles.isEmpty {
            throw VideoMergerError.exportFailed(nil)
        }
        
        // Then stitch all merged files together
        print("\n🎬 Stitching \(mergedFiles.count) merged files together...")
        let stitchedURL: URL
        do {
            stitchedURL = try await stitchVideos(videoURLs: mergedFiles, outputURL: outputURL)
            
            // Clean up the intermediate merged files after successful stitching
            for url in mergedFiles {
                try? FileManager.default.removeItem(at: url)
                print("🗑️ Cleaned up merged file: \(url.lastPathComponent)")
            }
        } catch {
            // Clean up the intermediate merged files if stitching failed
            for url in mergedFiles {
                try? FileManager.default.removeItem(at: url)
                print("🗑️ Cleaned up merged file after error: \(url.lastPathComponent)")
            }
            throw error
        }
        
        print("\n📊 Final Processing Summary:")
        print("├─ Total pairs: \(pairs.count)")
        print("├─ Successfully merged: \(mergedFiles.count)")
        print("└─ Final video: \(stitchedURL.lastPathComponent)")
        
        return stitchedURL
    }
    
    /// Stitches multiple MP4 files together in sequence
    /// - Parameters:
    ///   - videoURLs: Array of URLs for the MP4 files to stitch together
    ///   - outputURL: URL where the final stitched video will be saved
    /// - Returns: URL of the stitched video file
    static func stitchVideos(videoURLs: [URL], outputURL: URL) async throws -> URL {
        print("\n🎬 Starting video stitching process...")
        print("├─ Number of videos: \(videoURLs.count)")
        
        // Create composition
        let composition = AVMutableComposition()
        
        // Create tracks for video and audio
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            print("❌ Failed to create composition tracks")
            throw VideoMergerError.exportSessionCreationFailed
        }
        
        // Keep track of current time for sequential insertion
        var currentTime = CMTime.zero
        
        // Process each video
        for (index, videoURL) in videoURLs.enumerated() {
            print("\n📼 Processing video \(index + 1) of \(videoURLs.count)")
            
            // Create asset
            let asset = AVURLAsset(url: videoURL)
            try await asset.load(.tracks, .duration)
            
            // Get video track
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                print("❌ No video track found in video \(index + 1)")
                continue
            }
            
            // Get audio track
            guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                print("❌ No audio track found in video \(index + 1)")
                continue
            }
            
            // Get the preferred transform of the first video to maintain consistent orientation
            if index == 0 {
                let preferredTransform = try await videoTrack.load(.preferredTransform)
                compositionVideoTrack.preferredTransform = preferredTransform
            }
            
            // Insert video track
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: asset.duration),
                of: videoTrack,
                at: currentTime
            )
            
            // Insert audio track
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: asset.duration),
                of: audioTrack,
                at: currentTime
            )
            
            // Update current time
            currentTime = CMTimeAdd(currentTime, asset.duration)
            print("✅ Added video \(index + 1) to timeline")
        }
        
        print("\n📤 Exporting stitched video...")
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            print("❌ Failed to create export session")
            throw VideoMergerError.exportSessionCreationFailed
        }
        
        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Export the file
        await exportSession.export()
        
        // Check export status
        if exportSession.status == .completed {
            print("✅ Export completed successfully")
            print("📁 Saved to: \(outputURL.lastPathComponent)")
            print("└─ Duration: \(CMTimeGetSeconds(currentTime))s")
            return outputURL
        } else {
            print("❌ Export failed with error: \(String(describing: exportSession.error))")
            throw VideoMergerError.exportFailed(exportSession.error)
        }
    }
} 