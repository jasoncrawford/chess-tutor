import SwiftUI

@main
struct ChessTutorApp: App {
    @UIApplicationDelegateAdaptor(ChessTutorAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let composition = CoachingPanelAccessibilityFixture.launchComposition {
                CoachingPanelAccessibilityFixture(composition: composition)
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
