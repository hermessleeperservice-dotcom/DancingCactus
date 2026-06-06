import SwiftUI
import AVFoundation

@main
struct DancingCactusApp: App {

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}
