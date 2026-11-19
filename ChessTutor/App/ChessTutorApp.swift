import SwiftUI

@main
struct ChessTutorApp: App {
    @UIApplicationDelegateAdaptor(ChessTutorAppDelegate.self) private var appDelegate
    private let hostedCoachingProvider: (any HostedCoachingTurning)? = {
        #if DEBUG
        if let fixture = HostedConfigurationUITestSupport.current {
            return HostedCoachingRuntime.resolveProvider(credentialStore: fixture.credentialStore)
        }
        #endif
        return HostedCoachingRuntime.resolveProvider()
    }()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let fixture = HostedConfigurationUITestSupport.current {
                HostedConfigurationUITestFixture(support: fixture, provider: hostedCoachingProvider)
            } else if ManagedGamesCoachingUITestFixture.isEnabled {
                ManagedGamesCoachingUITestFixture()
            } else if HostedCoachingContinuityUITestFixture.isEnabled {
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
