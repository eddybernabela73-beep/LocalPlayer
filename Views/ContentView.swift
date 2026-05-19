import SwiftUI

struct ContentView: View {
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                LibraryView()
            }
            .safeAreaInset(edge: .bottom) {
                // Reserve space so the list doesn't hide behind the mini player
                Color.clear.frame(height: vm.currentTrack != nil ? 90 : 0)
            }

            if vm.currentTrack != nil {
                MiniPlayerView()
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.15), value: vm.currentTrack?.id)
        .sheet(isPresented: Binding(
            get: { vm.showPlayer },
            set: { vm.showPlayer = $0 }
        )) {
            PlayerView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
        }
    }
}
