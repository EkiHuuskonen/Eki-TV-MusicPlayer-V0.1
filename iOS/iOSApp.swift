import SwiftUI

@main
struct EkiTVMusicPlayerApp: App {
    @State private var player = Player()
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
                .environment(library)
        }
    }
}
