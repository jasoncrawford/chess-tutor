import SwiftUI

@main
struct ChessTutorApp: App {
    @UIApplicationDelegateAdaptor(ChessTutorAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
