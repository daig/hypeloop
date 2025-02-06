import Foundation
import CryptoKit

class BloomFilter {
    private var bitArray: [Bool]
    private let size: Int
    private let numHashes: Int
    
    init(size: Int = 10000, numHashes: Int = 3) {
        self.size = size
        self.numHashes = numHashes
        self.bitArray = Array(repeating: false, count: size)
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
        return abs(hash.hashValue)
    }
    
    // Serialize the filter to Data for storage
    func serialize() -> Data {
        return try! JSONEncoder().encode(bitArray)
    }
    
    // Create filter from serialized Data
    static func deserialize(_ data: Data) -> BloomFilter {
        let filter = BloomFilter()
        filter.bitArray = (try? JSONDecoder().decode([Bool].self, from: data)) ?? Array(repeating: false, count: 10000)
        return filter
    }
}
