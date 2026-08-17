import SwiftUI

@main
struct ChessTutorApp: App {
    @UIApplicationDelegateAdaptor(ChessTutorAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let configuration = CoachingPanelAccessibilityFixture.launchConfiguration {
                CoachingPanelAccessibilityFixture(configuration: configuration)
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
