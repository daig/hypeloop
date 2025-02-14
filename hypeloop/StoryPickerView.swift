import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct StoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedStoryId: String?
    @State private var stories: [(id: String, keywords: [String])] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.1, green: 0.1, blue: 0.15)
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                } else if stories.isEmpty {
                    Text("No stories found")
                        .foregroundColor(.white)
                } else {
                    List(stories, id: \.id) { story in
                        Button(action: {
                            selectedStoryId = story.id
                            dismiss()
                        }) {
                            VStack(alignment: .leading) {
                                Text("Story ID: \(story.id)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Keywords: \(story.keywords.joined(separator: ", "))")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .listRowBackground(Color(red: 0.2, green: 0.2, blue: 0.3))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Select a Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadStories()
        }
    }
    
    private func loadStories() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Please sign in to view stories"
            isLoading = false
            return
        }
        
        db.collection("stories")
            .whereField("userId", isEqualTo: userId)
            .order(by: "created_at", descending: true)
            .getDocuments { snapshot, error in
                isLoading = false
                
                if let error = error {
                    errorMessage = "Error loading stories: \(error.localizedDescription)"
                    return
                }
                
                stories = snapshot?.documents.compactMap { doc -> (id: String, keywords: [String])? in
                    let data = doc.data()
                    guard let keywords = data["keywords"] as? [String] else { return nil }
                    return (id: doc.documentID, keywords: keywords)
                } ?? []
            }
    }
} 