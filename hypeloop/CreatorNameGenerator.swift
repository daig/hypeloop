import Foundation
import CryptoKit

struct CreatorNameGenerator {
    // Lists for generating readable pseudorandom names
    private static let adjectives = [
        // Tech & Future
        "quantum", "cyber", "digital", "neural", "crypto", "techno", "hyper", "mega",
        "nano", "binary", "vector", "pixel", "virtual", "atomic", "sonic", "plasma",
        "laser", "matrix", "cloud", "data", "synth", "tech", "bio", "mecha",
        
        // Light & Color
        "neon", "chrome", "silver", "golden", "crystal", "prism", "flash", "glow",
        "spark", "bright", "blazing", "radiant", "shining", "gleam", "vivid", "flux",
        "aurora", "nebula", "gamma", "photon",
        
        // Space & Cosmic
        "cosmic", "astral", "lunar", "solar", "stellar", "galactic", "orbital", "nova",
        "pulsar", "quasar", "void", "eclipse", "meteor", "comet", "zodiac", "nebular",
        "celestial", "cosmic", "starlit", "astro",
        
        // Movement & Energy
        "swift", "rapid", "turbo", "surge", "pulse", "rush", "blast", "dash",
        "zoom", "bolt", "burst", "flow", "drift", "glide", "soar", "hover",
        "thrust", "power", "boost", "warp",
        
        // Mystical & Abstract
        "mystic", "crypto", "enigma", "phantom", "shadow", "spirit", "dream", "echo",
        "chaos", "zenith", "apex", "prime", "elite", "ultra", "omni", "multi",
        "infinity", "eternal", "supreme", "maximum",
        
        // Style & Aesthetic
        "retro", "vintage", "neo", "proto", "meta", "ultra", "poly", "flex",
        "fusion", "hybrid", "remix", "mod", "core", "punk", "wave", "funk",
        "glitch", "vibe", "trend", "style"
    ]
    
    private static let nouns = [
        // Mythical Creatures
        "dragon", "phoenix", "griffin", "hydra", "sphinx", "wyrm", "titan", "giant",
        "chimera", "kraken", "leviathan", "basilisk", "unicorn", "pegasus", "manticore", "drake",
        "wyvern", "behemoth", "cyclops", "siren",
        
        // Predators & Power Animals
        "wolf", "tiger", "lion", "panther", "jaguar", "leopard", "falcon", "eagle",
        "hawk", "owl", "raven", "cobra", "viper", "python", "shark", "orca",
        "lynx", "bear", "mantis", "scorpion",
        
        // Tech & Cyber
        "byte", "core", "node", "grid", "nexus", "matrix", "cipher", "vector",
        "proxy", "server", "router", "codec", "cache", "pixel", "shader", "script",
        "bot", "drone", "mech", "unit",
        
        // Space & Cosmic
        "star", "nova", "pulsar", "quasar", "comet", "meteor", "nebula", "galaxy",
        "void", "orbit", "solar", "lunar", "astro", "cosmos", "zenith", "aurora",
        "horizon", "eclipse", "storm", "flare",
        
        // Elements & Nature
        "flame", "frost", "storm", "thunder", "quake", "tide", "crystal", "prism",
        "blade", "spark", "beam", "wave", "pulse", "flash", "blast", "surge",
        "vortex", "vertex", "nexus", "flux",
        
        // Abstract & Cyber
        "ghost", "phantom", "shadow", "spirit", "soul", "mind", "echo", "enigma",
        "paradox", "riddle", "signal", "glitch", "error", "bug", "hack", "code",
        "data", "crypto", "cyber", "tech"
    ]
    
    /// Generates a deterministic hash from the input string
    static func generateCreatorHash(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Generates a display name from a hash
    static func generateDisplayName(from hash: String) -> String {
        // Use first 8 bytes of hash for seeding
        let seed = Int(hash.prefix(8), radix: 16) ?? 0
        var generator = SeededRandomNumberGenerator(seed: UInt64(seed))
        
        // Use the generator to pick words
        let adjIndex = Int.random(in: 0..<adjectives.count, using: &generator)
        let nounIndex = Int.random(in: 0..<nouns.count, using: &generator)
        
        return "\(adjectives[adjIndex])\(nouns[nounIndex])"
    }
}

// Custom random number generator for deterministic results
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var seed: UInt64
    
    init(seed: UInt64) {
        self.seed = seed
    }
    
    mutating func next() -> UInt64 {
        // Simple xoshiro256** algorithm
        seed = seed &* 6364136223846793005 &+ 1
        
        var result = seed
        result ^= result >> 12
        result ^= result << 25
        result ^= result >> 27
        return result &* 0x2545F4914F6CDD1D
    }
}
