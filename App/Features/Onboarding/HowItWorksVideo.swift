import AVKit
import SwiftUI

/// The optional how-it-works clip. Add `HowItWorks.mp4` to App/Resources to show
/// it in onboarding and in Setup › How It Works (see docs/shortcuts.md). Without
/// the file the slot takes no space at all.
enum HowItWorksVideo {
    /// Looked up once, synchronously, so visibility never depends on a view
    /// appearing. An `.onAppear` on an empty view never fires, so a check made
    /// there would leave the slot hidden forever.
    static let url: URL? = Bundle.main.url(forResource: "HowItWorks", withExtension: "mp4")
}

/// The video, or nothing when no clip is bundled.
struct HowItWorksVideoSlot: View {
    var body: some View {
        if let url = HowItWorksVideo.url {
            HowItWorksVideoPlayer(url: url)
        }
    }
}

private struct HowItWorksVideoPlayer: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        // The player is created in `.task` on the (never empty) VideoPlayer, and
        // doesn't autoplay: the user taps play.
        VideoPlayer(player: player)
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 420)
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityLabel(Text("Video: how capture works"))
            .task {
                if player == nil {
                    player = AVPlayer(url: url)
                }
            }
            .onDisappear {
                player?.pause()
            }
    }
}

#Preview {
    HowItWorksVideoSlot()
        .padding()
}
