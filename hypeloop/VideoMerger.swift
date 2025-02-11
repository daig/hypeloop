import AVFoundation
import Foundation

enum VideoMergerError: Error {
    case videoTrackNotFound
    case audioTrackNotFound
    case exportSessionCreationFailed
    case exportFailed(Error?)
    case assetCreationFailed
    case silenceGenerationFailed
}

class VideoMerger {
    /// Merges an audio file with a video file, replacing the video's original audio track.
    /// If the audio is longer than the video, the last frame of the video will be extended.
    /// If the audio is shorter than the video, silence will be added to pad the audio.
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
        
        // Case A: Audio is longer than video
        if audioDuration > videoDuration {
            print("├─ Case: Audio is longer than video")
            print("├─ Strategy: Extending last video frame")
            print("└─ Extension needed: \(String(format: "%.2f", audioDuration - videoDuration))s")
            
            // Insert the video track for its full duration
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoAsset.duration),
                of: videoTrack,
                at: .zero
            )
            
            // Create a freeze frame for the remaining duration
            let extraDuration = CMTime(seconds: audioDuration - videoDuration, preferredTimescale: 600)
            let lastFrameTime = CMTimeSubtract(videoAsset.duration, CMTime(value: 1, timescale: 30))
            
            print("🖼️ Creating freeze frame...")
            // Insert the freeze frame
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: lastFrameTime, duration: CMTime(value: 1, timescale: 30)),
                of: videoTrack,
                at: videoAsset.duration
            )
            
            // Set the time mapping to hold the last frame
            let timeRange = CMTimeRangeMake(start: videoAsset.duration, duration: extraDuration)
            compositionVideoTrack.scaleTimeRange(timeRange, toDuration: extraDuration)
            
            // Insert the full audio track
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: audioAsset.duration),
                of: audioTrack,
                at: .zero
            )
            print("✅ Successfully extended video with freeze frame")
        }
        // Case B: Audio is shorter than video
        else if audioDuration < videoDuration {
            print("├─ Case: Audio is shorter than video")
            print("├─ Strategy: Adding silence padding")
            print("└─ Padding needed: \(String(format: "%.2f", videoDuration - audioDuration))s")
            
            // Insert the full video track
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoAsset.duration),
                of: videoTrack,
                at: .zero
            )
            
            // Generate silence for padding
            let silenceDuration = (videoDuration - audioDuration) / 2
            print("🔇 Generating silence padding...")
            print("├─ Padding at start: \(String(format: "%.2f", silenceDuration))s")
            print("└─ Padding at end: \(String(format: "%.2f", silenceDuration))s")
            
            let silenceURL = try await generateSilence(duration: silenceDuration)
            let silenceAsset = AVURLAsset(url: silenceURL)
            try await silenceAsset.load(.tracks)
            
            guard let silenceTrack = try await silenceAsset.loadTracks(withMediaType: .audio).first else {
                print("❌ Failed to generate silence track")
                throw VideoMergerError.silenceGenerationFailed
            }
            
            // Insert silence at the beginning
            let silenceTime = CMTime(seconds: silenceDuration, preferredTimescale: 44100)
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: silenceTime),
                of: silenceTrack,
                at: .zero
            )
            
            print("🎵 Inserting audio with padding...")
            // Insert the audio track
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: audioAsset.duration),
                of: audioTrack,
                at: silenceTime
            )
            
            // Insert silence at the end
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: silenceTime),
                of: silenceTrack,
                at: CMTimeAdd(silenceTime, audioAsset.duration)
            )
            
            // Clean up silence file
            try? FileManager.default.removeItem(at: silenceURL)
            print("✅ Successfully added silence padding")
        }
        // Case C: Durations match
        else {
            print("├─ Case: Durations match exactly")
            print("└─ No adjustment needed")
            
            // Insert the video track
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoAsset.duration),
                of: videoTrack,
                at: .zero
            )
            
            // Insert the audio track
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: audioAsset.duration),
                of: audioTrack,
                at: .zero
            )
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
    
    /// Generates a silent audio file of specified duration
    /// - Parameter duration: Duration of silence in seconds
    /// - Returns: URL to the generated silence file
    private static func generateSilence(duration: Double) async throws -> URL {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let audioEngine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        
        // Create a buffer of silence
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        // The buffer is automatically initialized with zeros (silence)
        
        // Set up the audio engine
        audioEngine.attach(player)
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
        
        // Prepare the output file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        let file = try AVAudioFile(
            forWriting: tempURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        
        // Schedule the buffer to play
        await player.scheduleBuffer(buffer, at: nil, options: .loops)
        
        // Install tap on the mixer to capture the output
        audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format) { (buffer, time) in
            try? file.write(from: buffer)
        }
        
        // Start the engine and player
        try audioEngine.start()
        player.play()
        
        // Wait for the duration
        do {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        } catch {
            // Clean up on error
            player.stop()
            audioEngine.mainMixerNode.removeTap(onBus: 0)
            audioEngine.stop()
            audioEngine.detach(player)
            throw error
        }
        
        // Stop everything and clean up
        player.stop()
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.detach(player)
        
        return tempURL
    }
} 