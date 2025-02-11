import AVFoundation
import Foundation

enum VideoMergerError: Error {
    case videoTrackNotFound
    case audioTrackNotFound
    case exportSessionCreationFailed
    case exportFailed(Error?)
}

class VideoMerger {
    /// Merges an audio file with a video file, replacing the video's original audio track.
    /// - Parameters:
    ///   - videoURL: URL of the video file
    ///   - audioURL: URL of the audio file to merge
    ///   - outputURL: URL where the merged video will be saved
    /// - Returns: URL of the merged video file
    static func mergeAudioIntoVideo(videoURL: URL, audioURL: URL, outputURL: URL) async throws -> URL {
        // Create AVAssets
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        
        // Load the assets
        try await videoAsset.load(.tracks)
        try await audioAsset.load(.tracks)
        
        // Create composition
        let composition = AVMutableComposition()
        
        // Get video track
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoMergerError.videoTrackNotFound
        }
        
        // Get audio track
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoMergerError.audioTrackNotFound
        }
        
        // Get the duration of both assets
        try await videoAsset.load(.duration)
        try await audioAsset.load(.duration)
        let videoDuration = videoAsset.duration
        
        // Insert the video track
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: videoTrack,
            at: .zero
        )
        
        // Insert the audio track
        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: audioTrack,
            at: .zero
        )
        
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
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
            return outputURL
        } else {
            throw VideoMergerError.exportFailed(exportSession.error)
        }
    }
} 