import Foundation
import FirebaseFirestore
import FirebaseAuth

class BloomFilterStore: ObservableObject {
    private let db = Firestore.firestore()
    @Published var bloomFilter: BloomFilter
    @Published private(set) var isLoaded = false
    private var userId: String? {
        Auth.auth().currentUser?.uid
    }
    
    init() {
        self.bloomFilter = BloomFilter()
        Task {
            await loadFromFirebase()
        }
    }
    
    func add(_ element: String) {
        bloomFilter.add(element)
        saveToFirebase()
    }
    
    func mightContain(_ element: String) -> Bool {
        // If not loaded yet, conservatively return false to avoid showing duplicates
        guard isLoaded else {
            return false
        }
        return bloomFilter.mightContain(element)
    }
    
    @MainActor
    private func loadFromFirebase() async {
        print("🌸 Starting bloom filter load process")
        guard let userId = userId else {
            print("🌸 No user ID available, using empty bloom filter")
            isLoaded = true
            return
        }
        
        do {
            print("🌸 Loading bloom filter for user \(userId)")
            let document = try await db.collection("bloom_filters").document(userId).getDocument()
            print("🌸 Document exists: \(document.exists)")
            
            if document.exists {
                print("🌸 Document data: \(String(describing: document.data()))")
            }
            
            if document.exists,
               let data = document.data()?["filter"] as? String,
               let decodedData = Data(base64Encoded: data) {
                print("🌸 Successfully loaded bloom filter from Firebase")
                print("🌸 Decoded data size: \(decodedData.count) bytes")
                self.bloomFilter = BloomFilter.deserialize(decodedData)
                print("🌸 Successfully created bloom filter from data")
                
                // Debug: Test some known video IDs
                let testIds = [
                    "3MCxJb9YfpSRLOyDGUiMHKLThIneIOKXS34O43LS2RU",
                    "hIPUFLpwSqxzNFBNr9BxL02AWxOLq001fPDlpgkPcv76A",
                    "deNVcBjqXAdSe00EJ4Hb67xj6SGCb7Qfb6SClQPnmc7k"
                ]
                
                print("🌸 DEBUG: Testing loaded bloom filter with known IDs:")
                for id in testIds {
                    let present = bloomFilter.mightContain(id)
                    print("🌸 DEBUG: Video \(id) present=\(present)")
                }
            } else {
                print("🌸 No existing bloom filter found, using empty one")
                if document.exists {
                    print("🌸 Document exists but data is invalid. Raw data: \(String(describing: document.data()))")
                }
            }
        } catch {
            print("🌸 Error loading bloom filter: \(error)")
            print("🌸 Error details: \((error as NSError).userInfo)")
        }
        
        isLoaded = true
        print("🌸 Bloom filter loading completed. Current state: empty=\(bloomFilter.isEmpty)")
    }
    
    private func saveToFirebase() {
        guard let userId = userId else { return }
        
        let filterData = bloomFilter.serialize().base64EncodedString()
        
        Task {
            do {
                try await db.collection("bloom_filters").document(userId).setData([
                    "filter": filterData,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
                print("🌸 Successfully saved bloom filter to Firebase")
            } catch {
                print("🌸 Error saving bloom filter: \(error)")
            }
        }
    }
}
