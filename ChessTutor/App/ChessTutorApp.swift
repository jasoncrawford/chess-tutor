import SwiftUI

@main
struct ChessTutorApp: App {
    @UIApplicationDelegateAdaptor(ChessTutorAppDelegate.self) private var appDelegate
    private let hostedCoachingProvider = HostedCoachingRuntime.resolveProvider()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if HostedCoachingContinuityUITestFixture.isEnabled {
                HostedCoachingContinuityUITestFixture()
            } else if CoachingContinuityUITestFixture.isEnabled {
                CoachingContinuityUITestFixture()
            } else if let configuration = CoachingPanelAccessibilityFixture.launchConfiguration {
                CoachingPanelAccessibilityFixture(configuration: configuration)
            } else {
                ContentView(hostedCoachingProvider: hostedCoachingProvider)
            }
            #else
            ContentView(hostedCoachingProvider: hostedCoachingProvider)
            #endif
        }
    }
}
