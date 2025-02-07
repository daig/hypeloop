import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit
import FirebaseFunctions
import FirebaseFirestore

class AuthService: ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var userIconData: Data?
    private var currentNonce: String?
    
    static let shared = AuthService()
    private let functions = Functions.functions(region: "us-central1")
    private let db = Firestore.firestore()
    
    private init() {
        // Set initial state based on current Firebase Auth state
        self.user = Auth.auth().currentUser
        self.isAuthenticated = Auth.auth().currentUser != nil
        
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isAuthenticated = user != nil
                if user != nil {
                    Task {
                        await self?.fetchUserIcon()
                    }
                } else {
                    self?.userIconData = nil
                }
            }
        }
    }
    
    // MARK: - User Icon Methods
    
    private func fetchUserIcon() async {
        guard let uid = user?.uid else { return }
        
        do {
            let docSnapshot = try await db.collection("user_icons").document(uid).getDocument()
            if let iconData = docSnapshot.data()?["icon_data"] as? String,
               let data = Data(base64Encoded: iconData) {
                await MainActor.run {
                    self.userIconData = data
                }
            } else {
                // No icon found, generate one
                await generateAndStoreUserIcon()
            }
        } catch {
            print("Error fetching user icon: \(error.localizedDescription)")
            // If there's an error fetching, try to generate a new one
            await generateAndStoreUserIcon()
        }
    }
    
    private func generateAndStoreUserIcon() async {
        guard let uid = user?.uid else { return }
        
        do {
            let callable = functions.httpsCallable("generateProfileGif")
            let data: [String: Any] = [
                "width": 200,
                "height": 200,
                "frameCount": 30,
                "delay": 100
            ]
            
            let result = try await callable.call(data)
            
            guard let resultData = result.data as? [String: Any],
                  let base64String = resultData["gif"] as? String,
                  let newGifData = Data(base64Encoded: base64String) else {
                return
            }
            
            // Store in Firestore
            try await db.collection("user_icons").document(uid).setData([
                "icon_data": base64String,
                "updated_at": Date().timeIntervalSince1970
            ])
            
            await MainActor.run {
                self.userIconData = newGifData
            }
        } catch {
            print("Error generating user icon: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Email/Password Methods
    
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        DispatchQueue.main.async {
            self.user = result.user
            self.isAuthenticated = true
        }
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        DispatchQueue.main.async {
            self.user = nil
            self.isAuthenticated = false
            self.userIconData = nil
        }
    }
    
    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        DispatchQueue.main.async {
            self.user = result.user
            self.isAuthenticated = true
        }
    }
    
    // MARK: - Apple Sign In Methods
    
    /// Generates a random nonce string.
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }
    
    /// Returns the SHA256 hash of the input string.
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Configures the given Apple ID request by generating a nonce and setting the scopes.
    func handleSignInWithAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }
    
    /// Processes the Apple sign-in completion.
    func handleSignInWithAppleCompletion(_ result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credential type"])
            }
            guard let nonce = currentNonce else {
                fatalError("Invalid state: a login callback was received, but no login request was sent.")
            }
            guard let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"])
            }
            
            // Create a Firebase credential using the Apple ID token and the original nonce.
            let credential = OAuthProvider.credential(
                withProviderID: "apple.com",
                idToken: idTokenString,
                rawNonce: nonce
            )
            let result = try await Auth.auth().signIn(with: credential)
            
            // Optionally update display name if available.
            if let fullName = appleIDCredential.fullName {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                try await changeRequest.commitChanges()
            }
            
            DispatchQueue.main.async {
                self.user = result.user
                self.isAuthenticated = true
            }
        case .failure(let error):
            throw error
        }
    }
}