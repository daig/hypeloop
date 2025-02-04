//
//  LoginView.swift
//  hypeloop
//
//  Created by David Girardo on 2/3/25.
//

import SwiftUI

struct LoginView: View {
    // Binding to the login state from the app entry point
    @Binding var isLoggedIn: Bool
    
    @State private var username: String = ""
    @State private var password: String = ""

    var body: some View {
        ZStack {
            // Full-page background image using hypeloopLogo
            Image("hypeloopLogo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea() // Ensures the image covers the entire screen

            // Login form overlay
            VStack(spacing: 20) {
                Spacer()
                
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .background(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .foregroundColor(.white)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .background(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .foregroundColor(.white)
                
                Button(action: {
                    // Stub login action: simply print credentials and toggle login state.
                    print("Login tapped with username: \(username) and password: \(password)")
                    isLoggedIn = true
                }) {
                    Text("Login")
                        .frame(maxWidth: .infinity)
                        .padding()
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
                }
                .padding(.bottom, 50) // Add some padding at the bottom
            }
            .padding()
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        // Provide a constant binding for preview purposes.
        LoginView(isLoggedIn: .constant(false))
    }
}
