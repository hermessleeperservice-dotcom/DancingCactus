import SwiftUI

struct VoiceStatusView: View {
    let state: VoiceListener.State

    private var label: String {
        switch state {
        case .idle:        return "🎤 Listening..."
        case .capturing:   return "⏺ Recording"
        case .playingBack: return "🔊 Playing back"
        case .cooldown:    return "↩ Ready"
        }
    }

    private var color: Color {
        switch state {
        case .idle:        return .white.opacity(0.5)
        case .capturing:   return .red
        case .playingBack: return .yellow
        case .cooldown:    return .white.opacity(0.7)
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.black.opacity(0.3), in: Capsule())
            .animation(.easeInOut(duration: 0.2), value: state)
    }
}
