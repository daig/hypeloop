import Foundation
import CryptoKit

class BloomFilter {
    var isEmpty: Bool {
        return !bitArray.contains(true)
    }
    private var bitArray: [Bool]
    private let size: Int
    private let numHashes: Int
    
    init(size: Int = 10000, numHashes: Int = 3) {
        self.size = size
        self.numHashes = numHashes
        self.bitArray = Array(repeating: false, count: size)
    }
    
    init(bitArray: [Bool], size: Int = 10000, numHashes: Int = 3) {
        self.bitArray = bitArray
        self.size = size
        self.numHashes = numHashes
    }
    
    func add(_ element: String) {
        print("🌸 Adding to bloom filter: \(element)")
        let previousState = mightContain(element)
        for i in 0..<numHashes {
            let hash = getHash(element, seed: i)
            bitArray[hash % size] = true
        }
        print("🌸 After adding \(element): was_present=\(previousState), is_present=\(mightContain(element))")
    }
    
    func mightContain(_ element: String) -> Bool {
        let indices = (0..<numHashes).map { i -> Int in
            let hash = getHash(element, seed: i)
            return hash % size
        }
        let result = indices.allSatisfy { bitArray[$0] }
        print("🌸 Checking bloom filter for \(element): present=\(result), indices=\(indices)")
        return result
    }
    
    private func getHash(_ element: String, seed: Int) -> Int {
        let seedString = "\(element)\(seed)"
        let data = Data(seedString.utf8)
        let hash = SHA256.hash(data: data)
        
        // Convert first 8 bytes of hash to Int64 for consistent hashing
        let hashBytes = Array(hash.prefix(8))
        let hashInt = hashBytes.withUnsafeBytes { bytes -> Int64 in
            bytes.load(as: Int64.self)
        }
        
        // Use abs to ensure positive value, but be careful with Int64.min
        return hashInt == Int64.min ? Int(Int64.max) : Int(abs(hashInt))
    }
    
    // Serialize the filter to Data for storage
    func serialize() -> Data {
        print("🌸 Serializing bloom filter: size=\(size), numHashes=\(numHashes), isEmpty=\(isEmpty)")
        let data = try! JSONEncoder().encode(bitArray)
        print("🌸 Serialized size: \(data.count) bytes")
        return data
    }
    
    // Create filter from serialized Data
    static func deserialize(_ data: Data) -> BloomFilter {
        print("🌸 Deserializing bloom filter from \(data.count) bytes")
        let filter = BloomFilter()
        if let bitArray = try? JSONDecoder().decode([Bool].self, from: data) {
            print("🌸 Successfully decoded bit array of size \(bitArray.count)")
            filter.bitArray = bitArray
        } else {
            print("🌸 Failed to decode bit array, using empty filter")
            filter.bitArray = Array(repeating: false, count: 10000)
        }
        print("🌸 Deserialized bloom filter: isEmpty=\(filter.isEmpty)")
        return filter
    }
}
