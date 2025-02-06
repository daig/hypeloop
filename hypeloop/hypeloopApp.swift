//
//  hypeloopApp.swift
//  hypeloop
//
//  Created by David Girardo on 2/3/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct hypeloopApp: App {
    @StateObject private var authService = AuthService.shared
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                ContentView(isLoggedIn: .constant(true))
            } else {
                LoginView(isLoggedIn: .constant(false))
            }
        }
    }
}
