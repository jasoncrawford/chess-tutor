import SwiftUI
#if DEBUG
import UIKit
#endif

@main
struct ChessTutorApp: App {
    #if DEBUG
    @UIApplicationDelegateAdaptor(CloudKitShareSpikeAppDelegate.self) private var cloudKitShareSpikeAppDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if CloudKitShareSpikeLaunchConfiguration.isEnabled(arguments: ProcessInfo.processInfo.arguments) {
                CloudKitShareSpikeView()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
