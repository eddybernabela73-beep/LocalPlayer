import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm

        Group {
            if vm.isLoading {
                loadingView
            } else if vm.tracks.isEmpty {
                emptyView
            } else {
                trackListView
            }
        }
        .navigationTitle("Biblioteca")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $vm.searchText, prompt: "Buscar canciones, artistas…")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !vm.tracks.isEmpty {
                    Menu {
                        Picker("Ordenar por", selection: $vm.sortMode) {
                            ForEach(SortMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: sortIcon(mode)).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .fontWeight(.semibold)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vm.showFilePicker = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .fileImporter(
            isPresented: $vm.showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                vm.loadFolder(url: url)
            }
        }
    }

    private func sortIcon(_ mode: SortMode) -> String {
        switch mode {
        case .title:    return "textformat"
        case .artist:   return "person"
        case .album:    return "square.stack"
        case .duration: return "clock"
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Cargando canciones…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 28) {
            Image(systemName: "music.note.list")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(.quaternary)

            VStack(spacing: 8) {
                Text("Sin música")
                    .font(.title2.bold())
                Text("Selecciona una carpeta de la app Archivos\npara empezar a escuchar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                vm.showFilePicker = true
            } label: {
                Label("Seleccionar carpeta", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Track List

    private var trackListView: some View {
        List {
            // Folder info + sort info
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text(vm.folderName)
                        .font(.subheadline)
                    Spacer()
                    Text(vm.searchText.isEmpty
                         ? "\(vm.tracks.count) canciones"
                         : "\(vm.displayTracks.count) de \(vm.tracks.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            // Tracks
            Section {
                if vm.displayTracks.isEmpty {
                    HStack {
                        Spacer()
                        Text("Sin resultados para \"\(vm.searchText)\"")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(vm.displayTracks) { track in
                        let isCurrent = vm.currentTrack?.id == track.id
                        TrackRow(
                            track: track,
                            isCurrent: isCurrent,
                            isPlaying: isCurrent && vm.isPlaying
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            vm.play(track: track)
                            vm.showPlayer = true
                        }
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Track Row

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            artworkView
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.callout)
                        .foregroundStyle(.blue)
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers)
                } else {
                    Text(track.durationFormatted)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 46, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork = track.artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(.systemGray5)
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
