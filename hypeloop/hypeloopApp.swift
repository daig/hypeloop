//
//  hypeloopApp.swift
//  hypeloop
//
//  Created by David Girardo on 2/3/25.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct hypeloopApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
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
