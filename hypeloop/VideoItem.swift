//
//  VideoItem.swift
//  hypeloop
//

import Foundation

struct VideoItem: Codable {
    let id: String
    let playback_id: String
    let creator: String       // Hash of the creator's identifier
    let display_name: String  // Generated display name
    let description: String
    let created_at: Double
    let status: String
    
    var playbackUrl: URL {
        URL(string: "https://stream.mux.com/\(playback_id).m3u8")!
    }
}