import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 14) {
            // Artwork
            artworkView
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.currentTrack?.title ?? "")
                    .font(.callout.bold())
                    .lineLimit(1)
                Text(vm.currentTrack?.artist ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Controls
            HStack(spacing: 20) {
                Button(action: vm.togglePlayPause) {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }

                Button(action: vm.playNext) {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.trailing, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        }
        .padding(.horizontal, 12)
        .onTapGesture {
            vm.showPlayer = true
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork = vm.currentTrack?.artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(.systemGray5)
                Image(systemName: "music.note")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
