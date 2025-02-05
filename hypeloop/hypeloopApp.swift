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
    @State private var isLoggedIn = false
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            if isLoggedIn {
                ContentView()
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
            }
        }
    }
}
