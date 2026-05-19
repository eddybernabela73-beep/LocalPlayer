import SwiftUI

struct PlayerView: View {
    @Environment(PlayerViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 14)

                Spacer().frame(height: 18)

                // Album artwork
                artworkSection
                    .padding(.horizontal, 38)

                Spacer().frame(height: 32)

                // Track title + artist
                trackInfoSection
                    .padding(.horizontal, 38)

                Spacer().frame(height: 22)

                // Progress bar
                progressSection
                    .padding(.horizontal, 38)

                Spacer().frame(height: 26)

                // Play / Prev / Next
                mainControls
                    .padding(.horizontal, 38)

                Spacer().frame(height: 22)

                // Shuffle + Repeat
                secondaryControls
                    .padding(.horizontal, 52)

                Spacer()
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let artwork = vm.currentTrack?.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 90, opaque: true)
                    .opacity(0.45)
                    .ignoresSafeArea()
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.15), location: 0),
                    .init(color: .black.opacity(0.65), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        ZStack {
            if let artwork = vm.currentTrack?.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white.opacity(0.08))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 72, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.3))
                    )
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 35, y: 18)
        .scaleEffect(vm.isPlaying ? 1.0 : 0.87)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: vm.isPlaying)
    }

    // MARK: - Track Info

    private var trackInfoSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(vm.currentTrack?.title ?? "—")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(vm.currentTrack?.artist ?? "")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: isDragging ? 7 : 4)

                    Capsule()
                        .fill(.white)
                        .frame(
                            width: geo.size.width * progressRatio,
                            height: isDragging ? 7 : 4
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            isDragging = true
                            dragProgress = (v.location.x / geo.size.width).clamped(0...1)
                        }
                        .onEnded { v in
                            let p = (v.location.x / geo.size.width).clamped(0...1)
                            vm.seek(to: p * vm.duration)
                            isDragging = false
                        }
                )
            }
            .frame(height: 20)
            .animation(.easeOut(duration: 0.12), value: isDragging)

            HStack {
                Text(formatTime(isDragging ? dragProgress * vm.duration : vm.currentTime))
                Spacer()
                Text(formatTime(vm.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var progressRatio: Double {
        if isDragging { return dragProgress }
        guard vm.duration > 0 else { return 0 }
        return (vm.currentTime / vm.duration).clamped(0...1)
    }

    // MARK: - Main Controls

    private var mainControls: some View {
        HStack(spacing: 0) {
            Button(action: vm.playPrevious) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            Button(action: vm.togglePlayPause) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 78, height: 78)
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.black)
                        .offset(x: vm.isPlaying ? 0 : 2)
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: vm.playNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Secondary Controls

    private var secondaryControls: some View {
        HStack {
            // Shuffle
            Button(action: vm.toggleShuffle) {
                VStack(spacing: 5) {
                    Image(systemName: "shuffle")
                        .font(.body)
                        .foregroundStyle(vm.isShuffled ? .white : .white.opacity(0.35))
                    Circle()
                        .fill(vm.isShuffled ? .white : .clear)
                        .frame(width: 4, height: 4)
                }
            }

            Spacer()

            // Repeat
            Button(action: vm.toggleRepeat) {
                VStack(spacing: 5) {
                    Image(systemName: vm.repeatMode.systemImage)
                        .font(.body)
                        .foregroundStyle(vm.repeatMode.isActive ? .white : .white.opacity(0.35))
                    Circle()
                        .fill(vm.repeatMode.isActive ? .white : .clear)
                        .frame(width: 4, height: 4)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Clamp helper

extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
