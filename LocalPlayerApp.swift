import SwiftUI

@main
struct LocalPlayerApp: App {
    @State private var viewModel = PlayerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
        }
    }
}
