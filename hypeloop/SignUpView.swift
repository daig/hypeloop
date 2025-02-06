import SwiftUI
import FirebaseAuth

struct SignUpView: View {
    @Binding var isLoggedIn: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthService.shared

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var errorMessage: String = ""
    @State private var isLoading = false

    private func handleAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        print("Debug - Error code: \(nsError.code), Domain: \(nsError.domain)")
        
        guard let errorCode = AuthErrorCode(_bridgedNSError: nsError) else {
            return "An error occurred. Please try again later."
        }
        
        switch errorCode {
        case .invalidEmail:
            return "Please enter a valid email address."
        case .emailAlreadyInUse:
            return "This email is already registered. Please try logging in instead."
        case .weakPassword:
            return "Password is too weak. Please use a stronger password."
        case .networkError:
            return "Network error. Please check your internet connection."
        default:
            print("Debug - Unhandled error code: \(errorCode)")
            return "An error occurred. Please try again."
        }
    }

    var body: some View {
        ZStack {
            // Full-page background image using hypeloopLogo
            GeometryReader { geometry in
                Image("hypeloopLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width * 1.2, height: geometry.size.height)
                    .clipped()
                    .position(x: geometry.size.width/2, y: geometry.size.height/2)
                    .ignoresSafeArea()
            }
            .ignoresSafeArea()

            // Sign Up form overlay
            VStack(spacing: 20) {
                Text("Create Account")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding(.top, 50)
                
                // Email field now tagged as username so that saved credentials associate correctly.
                TextField("Email", text: $email)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .background(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .foregroundColor(.white)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                
                // Password field marked as newPassword to trigger strong password suggestions.
                SecureField("Password", text: $password)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .background(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .foregroundColor(.white)
                    .textContentType(.newPassword)
                    .autocapitalization(.none)
                
                // Confirm password field no longer has a newPassword hint to avoid autofill conflict.
                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .background(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .foregroundColor(.white)
                    .textContentType(.none)
                    .autocapitalization(.none)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
                
                Button(action: {
                    Task {
                        if password != confirmPassword {
                            errorMessage = "Passwords do not match"
                            return
                        }
                        
                        isLoading = true
                        do {
                            try await authService.signUp(email: email, password: password)
                            isLoggedIn = true
                        } catch {
                            errorMessage = handleAuthError(error)
                        }
                        isLoading = false
                    }
                }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Sign Up")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.2, green: 0.2, blue: 0.3),
                            Color(red: 0.3, green: 0.2, blue: 0.4)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding(.horizontal)
                .disabled(isLoading)
                
                Button(action: {
                    dismiss()
                }) {
                    Text("Already have an account? Log in")
                        .foregroundColor(.white)
                }
                .padding(.top, 10)
                
                Spacer()
            }
            .padding()
        }
    }
}
