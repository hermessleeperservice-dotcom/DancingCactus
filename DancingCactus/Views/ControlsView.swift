import SwiftUI

struct ControlsView: View {
    @Bindable var musicPlayer: MusicPlayer
    let parrotMode: ParrotMode

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 36) {
                controlButton(icon: "backward.fill", size: 28) {
                    musicPlayer.previous()
                }

                controlButton(icon: musicPlayer.isPlaying ? "pause.fill" : "play.fill", size: 36, diameter: 72) {
                    musicPlayer.togglePlayPause()
                }
                .scaleEffect(musicPlayer.isPlaying ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: musicPlayer.isPlaying)

                controlButton(icon: "forward.fill", size: 28) {
                    musicPlayer.next()
                }
            }

            Button {
                if parrotMode.isActive { parrotMode.deactivate() } else { parrotMode.activate() }
            } label: {
                Image(systemName: parrotMode.isActive ? "waveform.badge.mic" : "mic.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(parrotMode.isActive ? Color.yellow : Color.white.opacity(0.5))
                    .frame(width: 40, height: 40)
                    .background(
                        parrotMode.isActive ? Color.yellow.opacity(0.25) : Color.white.opacity(0.1),
                        in: Circle()
                    )
                    .overlay(
                        Circle().stroke(
                            parrotMode.isActive ? Color.yellow.opacity(0.6) : Color.clear,
                            lineWidth: 1.5
                        )
                    )
            }
            .offset(x: 80, y: 20)
        }
    }

    @ViewBuilder
    private func controlButton(
        icon: String,
        size: CGFloat,
        diameter: CGFloat = 52,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(.white.opacity(0.2), in: Circle())
        }
    }
}
