import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var musicPlayer = MusicPlayer()
    @State private var voiceListener = VoiceListener()
    @State private var parrotMode = ParrotMode()

    var body: some View {
        ZStack {
            CactusView(
                isPlaying: musicPlayer.isPlaying,
                beatPhase: musicPlayer.beatPhase,
                isWiggling: parrotMode.isWiggling
            )
            .ignoresSafeArea()
            .onTapGesture { musicPlayer.togglePlayPause() }
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .global)
                    .onEnded { val in
                        if val.translation.width < -50 { musicPlayer.next() }
                        else if val.translation.width > 50 { musicPlayer.previous() }
                    }
            )

            VStack {
                // Voice status indicator at top
                if !parrotMode.isActive {
                    VoiceStatusView(state: voiceListener.state)
                        .padding(.top, 60)
                }
                Spacer()
                SongTitleView(song: musicPlayer.currentSong)
                    .padding(.bottom, 24)
                ControlsView(musicPlayer: musicPlayer, parrotMode: parrotMode)
                    .padding(.bottom, 52)
            }
        }
        .task {
            await requestMicPermission()
            voiceListener.start()
        }
        .onChange(of: parrotMode.isActive) { _, active in
            // Only one AVAudioEngine can hold an input tap at a time
            if active {
                voiceListener.stop()
            } else {
                voiceListener.start()
            }
        }
        .onDisappear {
            voiceListener.stop()
            if parrotMode.isActive { parrotMode.deactivate() }
        }
    }

    private func requestMicPermission() async {
        if #available(iOS 17.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted { print("Microphone permission denied") }
        } else {
            await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { _ in cont.resume() }
            }
        }
    }
}

#Preview { ContentView() }
