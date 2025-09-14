import SwiftUI

@main
struct inDriveApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack { DamageDetectorView() }
        }
    }
}
