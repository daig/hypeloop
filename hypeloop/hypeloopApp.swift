//
//  hypeloopApp.swift
//  hypeloop
//
//  Created by David Girardo on 2/3/25.
//

import SwiftUI

@main
struct hypeloopApp: App {
    // Initially false – user is not logged in
    @State private var isLoggedIn = false

    var body: some Scene {
        WindowGroup {
            if isLoggedIn {
                ContentView()
            } else {
                // Pass the binding so LoginView can change it on login
                LoginView(isLoggedIn: $isLoggedIn)
            }
        }
    }
}
