import SwiftUI

struct LyricsView: View {
    @Environment(PlayerViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.lyricsLoading {
                    loadingView
                } else if vm.lyricsError || vm.lyrics.isEmpty {
                    errorView
                } else {
                    lyricsScrollView
                }
            }
            .navigationTitle("Letra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if vm.lyrics.isEmpty && !vm.lyricsLoading {
                vm.fetchLyrics()
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Buscando letra…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(.quaternary)

            VStack(spacing: 8) {
                Text("Letra no encontrada")
                    .font(.title3.bold())
                Text("No se encontró la letra de\n\"\(vm.currentTrack?.title ?? "esta canción")\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                vm.fetchLyrics()
            } label: {
                Label("Intentar de nuevo", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Lyrics

    private var lyricsScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Track info header
                HStack(spacing: 12) {
                    if let artwork = vm.currentTrack?.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vm.currentTrack?.title ?? "")
                            .font(.headline)
                            .lineLimit(1)
                        Text(vm.currentTrack?.artist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.bottom, 8)

                Divider()

                // Lyrics text
                Text(vm.lyrics)
                    .font(.body)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
    }
}
