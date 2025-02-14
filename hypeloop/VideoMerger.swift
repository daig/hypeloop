import AVFoundation
import Foundation
import FirebaseFirestore
import UIKit

enum VideoMergerError: Error {
    case videoTrackNotFound
    case audioTrackNotFound
    case exportSessionCreationFailed
    case exportFailed(Error?)
    case assetCreationFailed
}

class VideoMerger {
    private static let db = Firestore.firestore()
    
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
    
    static func mergeStoryAssets(storyId: String, useMotion: Bool, progressCallback: @escaping (String) -> Void) async throws -> URL {
        print("🎬 Starting merge process for story: \(storyId)")
        print("🎥 Using \(useMotion ? "motion videos" : "static images")")
        
        // Get all audio and image assets for this story
        let audioQuery = db.collection("audio").whereField("storyId", isEqualTo: storyId)
        let imageQuery = db.collection("images").whereField("storyId", isEqualTo: storyId)
        
        let audioSnapshot = try await audioQuery.getDocuments()
        let imageSnapshot = try await imageQuery.getDocuments()
        
        print("Found \(audioSnapshot.documents.count) audio files and \(imageSnapshot.documents.count) images")
        
        // Sort assets by sceneNumber
        let audioAssets = audioSnapshot.documents
            .compactMap { doc -> (sceneNumber: Int, downloadUrl: String?)? in
                let data = doc.data()
                guard let sceneNumber = data["sceneNumber"] as? Int else { return nil }
                let downloadUrl = data["download_url"] as? String
                return (sceneNumber, downloadUrl)
            }
            .sorted { $0.sceneNumber < $1.sceneNumber }
        
        let imageAssets = imageSnapshot.documents
            .compactMap { doc -> (sceneNumber: Int, url: String, motion: Bool, motionUrl: String?)? in
                let data = doc.data()
                guard let sceneNumber = data["sceneNumber"] as? Int,
                      let url = data["url"] as? String else { return nil }
                let motion = data["motion"] as? Bool ?? false
                let motionUrl = data["motion_url"] as? String
                return (sceneNumber, url, motion, motionUrl)
            }
            .sorted { $0.sceneNumber < $1.sceneNumber }
        
        print("🔄 Processing:")
        print("🎵 Audio assets: \(audioAssets.map { $0.sceneNumber })")
        print("🖼️ Image assets: \(imageAssets.map { $0.sceneNumber })")
        
        // Create temporary directory for downloaded files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Download all assets
        var pairs: [(videoURL: URL, audioURL: URL)] = []
        var downloadedAudioFiles: Set<Int> = []
        var downloadedVideoFiles: Set<Int> = []
        
        // Download audio files
        for asset in audioAssets {
            progressCallback("Downloading audio \(asset.sceneNumber + 1) of \(audioAssets.count)...")
            let audioURL = tempDir.appendingPathComponent("audio_\(asset.sceneNumber).mp3")
            
            guard let downloadUrl = asset.downloadUrl else {
                print("⚠️ No download URL for scene \(asset.sceneNumber)")
                continue
            }
            
            do {
                let (audioData, _) = try await URLSession.shared.data(from: URL(string: downloadUrl)!)
                try audioData.write(to: audioURL)
                downloadedAudioFiles.insert(asset.sceneNumber)
                print("✅ Downloaded audio for scene \(asset.sceneNumber)")
            } catch {
                print("❌ Error downloading audio for scene \(asset.sceneNumber): \(error)")
                continue
            }
        }
        
        // Get all motion videos for this story at once
        let motionVideosQuery = db.collection("motion_videos")
            .whereField("storyId", isEqualTo: storyId)
            .whereField("status", isEqualTo: "ready")  // Only get ready videos
        print("🔍 Querying motion_videos with storyId: \(storyId)")
        let motionVideosSnapshot = try await motionVideosQuery.getDocuments()
        
        // Create a dictionary mapping scene numbers to motion video data
        let motionVideosByScene = Dictionary(
            uniqueKeysWithValues: motionVideosSnapshot.documents.compactMap { doc -> (Int, String)? in
                let data = doc.data()
                guard let sceneNumber = data["sceneNumber"] as? Int,
                      let status = data["status"] as? String,
                      status == "ready",
                      let playbackId = data["playbackId"] as? String else {
                    print("⚠️ Skipping document \(doc.documentID) - Status: \(data["status"] ?? "unknown")")
                    return nil
                }
                print("🔍 Found ready motion video - Scene: \(sceneNumber), PlaybackID: \(playbackId)")
                return (sceneNumber, playbackId)
            }
        )
        
        print("🎥 Found \(motionVideosByScene.count) motion videos")
        print("📋 Motion videos available for scenes: \(Array(motionVideosByScene.keys).sorted())")
        
        // Download and process image/video files
        for asset in imageAssets {
            progressCallback("Processing scene \(asset.sceneNumber + 1) of \(imageAssets.count)...")
            
            do {
                let videoURL: URL
                
                if useMotion && asset.motion {
                    print("🔎 Looking for motion video for scene \(asset.sceneNumber)")
                    // Check if we have a motion video for this scene
                    if let playbackId = motionVideosByScene[asset.sceneNumber] {
                        print("🎥 Found motion video playback ID: \(playbackId) for scene \(asset.sceneNumber)")
                        
                        // Download the motion video to local storage first
                        let tempDir = FileManager.default.temporaryDirectory
                        let localVideoURL = tempDir.appendingPathComponent("motion_video_\(asset.sceneNumber).mp4")
                        
                        print("📥 Downloading motion video to: \(localVideoURL)")
                        let (downloadedData, _) = try await URLSession.shared.data(from: URL(string: playbackId)!)
                        try downloadedData.write(to: localVideoURL)
                        
                        videoURL = localVideoURL
                        print("✅ Downloaded and saved motion video for scene \(asset.sceneNumber)")
                    } else {
                        print("⚠️ Motion video not found for scene \(asset.sceneNumber)")
                        guard let downloadURL = URL(string: asset.url) else {
                            print("⚠️ Invalid image URL for scene \(asset.sceneNumber)")
                            continue
                        }
                        let (imageData, _) = try await URLSession.shared.data(from: downloadURL)
                        videoURL = try await createVideoFromImage(imageData: imageData)
                        print("✅ Created video from static image for scene \(asset.sceneNumber)")
                    }
                } else {
                    // Use static image
                    print("🖼️ Using static image for scene \(asset.sceneNumber)")
                    guard let downloadURL = URL(string: asset.url) else {
                        print("⚠️ Invalid image URL for scene \(asset.sceneNumber)")
                        continue
                    }
                    let (imageData, _) = try await URLSession.shared.data(from: downloadURL)
                    videoURL = try await createVideoFromImage(imageData: imageData)
                    print("✅ Created video from static image for scene \(asset.sceneNumber)")
                }
                
                downloadedVideoFiles.insert(asset.sceneNumber)
                
                // Check if we have both audio and video for this scene
                if downloadedAudioFiles.contains(asset.sceneNumber) {
                    let audioURL = tempDir.appendingPathComponent("audio_\(asset.sceneNumber).mp3")
                    if FileManager.default.fileExists(atPath: audioURL.path) {
                        pairs.append((videoURL: videoURL, audioURL: audioURL))
                        print("🔗 Created pair for scene \(asset.sceneNumber)")
                    }
                }
            } catch {
                print("❌ Error processing scene \(asset.sceneNumber): \(error)")
                continue
            }
        }
        
        if pairs.isEmpty {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid pairs found to merge"])
        }
        
        // Process pairs and stitch them together
        progressCallback("Merging assets...")
        let outputURL = tempDir.appendingPathComponent("final_\(UUID().uuidString).mp4")
        
        let stitchedURL = try await processPairsAndStitch(
            pairs: pairs,
            outputURL: outputURL
        )
        
        // Clean up temporary directory except for the final stitched video
        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url != stitchedURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        return stitchedURL
    }
    
    private static func createVideoFromImage(imageData: Data, duration: Double = 3.0) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let videoURL = tempDir.appendingPathComponent("\(UUID().uuidString).mp4")
        
        // Create AVAssetWriter
        let assetWriter = try AVAssetWriter(url: videoURL, fileType: .mp4)
        
        // Create video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 512,
            AVVideoHeightKey: 512,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2000000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        // Create writer input
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = true
        
        // Create pixel buffer adapter
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 512,
            kCVPixelBufferHeightKey as String: 512
        ]
        
        let adapter = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: attributes
        )
        
        assetWriter.add(writerInput)
        try await assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        
        // Create UIImage from data
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image from data"])
        }
        
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        try CVPixelBufferCreate(
            kCFAllocatorDefault,
            512,
            512,
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard let buffer = pixelBuffer else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
        }
        
        // Lock buffer and draw image into it
        CVPixelBufferLockBaseAddress(buffer, [])
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: pixelData,
            width: 512,
            height: 512,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
        }
        
        // Draw image
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        // Write frames
        let frameCount = Int(duration * 24) // 24 fps
        
        // Set up the writer input once, outside the loop
        writerInput.requestMediaDataWhenReady(on: .main) {
            // The block intentionally left empty - we'll handle writing in our loop
        }
        
        for frameNumber in 0..<frameCount {
            let presentationTime = CMTime(value: CMTimeValue(frameNumber), timescale: 24)
            
            // Simple polling with a short sleep
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms sleep
            }
            
            adapter.append(buffer, withPresentationTime: presentationTime)
        }
        
        // Finish writing
        writerInput.markAsFinished()
        await assetWriter.finishWriting()
        
        return videoURL
    }
} 