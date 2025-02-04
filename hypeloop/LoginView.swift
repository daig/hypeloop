//
//  LoginView.swift
//  hypeloop
//
//  Created by David Girardo on 2/3/25.
//

import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @StateObject private var authService = AuthService.shared
    @State private var showSignUp = false
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String = ""
    @State private var isLoading = false
    
    private func handleAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        print("Debug - Error code: \(nsError.code), Domain: \(nsError.domain)")
        
        // Handle the generic "malformed credential" error which is now used for both wrong password and non-existent user
        if nsError.localizedDescription.contains("malformed or has expired") {
            return "Invalid email or password. Please check your credentials and try again."
        }
        
        // Handle other specific cases that are still reported
        guard let errorCode = AuthErrorCode(_bridgedNSError: nsError) else {
            return "An error occurred. Please try again later."
        }
        
        switch errorCode {
        case .invalidEmail:
            return "Please enter a valid email address."
        case .tooManyRequests:
            return "Too many attempts. Please try again later."
        case .networkError:
            return "Network error. Please check your internet connection."
        case .userDisabled:
            return "This account has been disabled. Please contact support."
        default:
            print("Debug - Unhandled error code: \(errorCode)")
            return "An error occurred. Please try again."
        }
    }
    
    var body: some View {
        NavigationStack {
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

                // Login form overlay
                VStack(spacing: 20) {
                    Spacer()
                    
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
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .foregroundColor(.white)
                        .textContentType(.password)
                        .autocapitalization(.none)
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button(action: {
                        Task {
                            isLoading = true
                            do {
                                try await authService.signIn(email: email, password: password)
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
                            Text("Login")
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
                    
                    NavigationLink(destination: SignUpView(isLoggedIn: $isLoggedIn)) {
                        Text("Don't have an account? Sign up")
                            .foregroundColor(.white)
                    }
                    .padding(.top, 10)
                    
                    .padding(.bottom, 50)
                }
                .padding()
            }
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(isLoggedIn: .constant(false))
    }
}
