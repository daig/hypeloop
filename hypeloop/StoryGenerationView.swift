import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

struct StoryGenerationView: View {
    @Binding var isGeneratingStory: Bool
    @Binding var selectedStoryId: String?
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    
    let numKeyframes: Int
    let onKeyframesChange: (Int) -> Void
    
    private let functions = Functions.functions(region: "us-central1")
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Generate Story")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Number of Keyframes")
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: .init(
                        get: { numKeyframes },
                        set: { onKeyframesChange($0) }
                    )) {
                        ForEach([4, 6, 8, 10], id: \.self) { num in
                            Text("\(num)").tag(num)
                        }
                    }
                    .pickerStyle(.menu)
                    .accentColor(.white)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                
                Button(action: {
                    Task {
                        await generateStory()
                    }
                }) {
                    HStack {
                        if isGeneratingStory {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(isGeneratingStory ? "Generating Story..." : "Generate New Story")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isGeneratingStory ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isGeneratingStory)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
        }
        .padding(.horizontal)
    }
    
    private func generateStory() async {
        do {
            let storyId = try await testStoryGeneration(numKeyframes: numKeyframes, isFullBuild: true)
            // Wait a bit to let assets start generating
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            print("🔄 Starting story incubation for ID: \(storyId)")
            selectedStoryId = storyId
            alertMessage = "Story is now incubating! Check the egg tab to see when it's ready."
            showAlert = true
            
            // Update story status to incubating
            try await db.collection("stories").document(storyId).updateData([
                "status": "incubating",
                "creator": Auth.auth().currentUser?.uid ?? "",
                "created_at": Int(Date().timeIntervalSince1970 * 1000),
                "num_keyframes": numKeyframes,
                "scenesRendered": 0
            ])
            
            isGeneratingStory = false
        } catch {
            print("❌ Story generation error: \(error)")
            if let authError = error as? AuthErrorCode {
                alertMessage = "Authentication error: \(authError.localizedDescription)"
            } else {
                alertMessage = "Story generation failed: \(error.localizedDescription)"
            }
            showAlert = true
            isGeneratingStory = false
        }
    }
    
    private func testStoryGeneration(numKeyframes: Int, isFullBuild: Bool) async throws -> String {
        isGeneratingStory = true
        
        guard let user = Auth.auth().currentUser else {
            print("❌ User not authenticated")
            alertMessage = "Please sign in to generate stories"
            isGeneratingStory = false
            showAlert = true
            throw NSError(domain: "StoryGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("✅ User authenticated: \(user.uid)")
        
        let callable = functions.httpsCallable("generateStoryFunction")
        
        let data: [String: Any] = [
            "keywords": ["magical forest", "lost child", "friendly dragon"],
            "config": [
                "extract_chars": true,
                "generate_voiceover": true,
                "generate_images": true,
                "generate_motion": true,
                "save_script": true,
                "num_keyframes": numKeyframes,
                "output_dir": "output"
            ]
        ]
        
        print("📤 Calling Cloud Function with data:", data)
        let result = try await callable.call(data)
        print("📥 Received response:", result.data)
        
        if let resultData = result.data as? [String: Any] {
            if let storyId = resultData["storyId"] as? String {
                print("✅ Story generation completed with ID: \(storyId)")
                alertMessage = "Story generation completed! Starting asset generation..."
                showAlert = true
                isGeneratingStory = false
                return storyId
            } else {
                throw NSError(domain: "StoryGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Story ID not found in response"])
            }
        } else {
            alertMessage = "Story generation completed but response format was unexpected"
            print("⚠️ Unexpected response format: \(result.data)")
            throw NSError(domain: "StoryGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
        }
    }
} 