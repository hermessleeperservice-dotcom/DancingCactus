import SwiftUI

struct SongTitleView: View {
    let song: Song?

    var body: some View {
        Text(song?.title ?? "Dancing Cactus")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeInOut(duration: 0.3), value: song?.id)
            .id(song?.id)
    }
}
